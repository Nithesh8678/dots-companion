import AppKit
import ApplicationServices
import ScreenCaptureKit

struct ContextSnapshot {
    let id: UUID
    let capturedAt: Date
    let appName: String
    let bundleID: String?
    let windowTitle: String
    let windowID: CGWindowID
    let displayID: CGDirectDisplayID
    /// Global Quartz coordinates, measured in points from the primary display's top left.
    let frame: CGRect
    let pixelSize: CGSize
    let image: NSImage
    let pngData: Data

    var pointsPerPixel: CGSize {
        CGSize(width: frame.width / pixelSize.width, height: frame.height / pixelSize.height)
    }

    func globalPoint(forImagePoint point: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + point.x * pointsPerPixel.width,
                y: frame.minY + point.y * pointsPerPixel.height)
    }
}

/// One explicit request produces one window image. No stream or screenshot is retained here.
@MainActor
final class ContextService {
    private var generation: UInt64 = 0
    private var capturing = false

    func cancel() { generation &+= 1 }

    func captureForegroundWindow(excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier) async throws -> ContextSnapshot {
        guard !capturing else { throw LocalServiceError.unavailable("A snapshot is already being captured.") }
        guard CGPreflightScreenCaptureAccess() else {
            throw LocalServiceError.permission("Allow Screen Recording to share one foreground-window snapshot. Nothing is captured continuously.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != excludingPID else {
            throw LocalServiceError.unavailable("Bring the window you want to share to the front, then use the shortcut.")
        }
        if AXIsProcessTrusted(), let focused = try? AccessibilitySupport.focusedElement(pid: app.processIdentifier) {
            // Refuse the whole capture when a known password field is focused. Other sensitive
            // window content still requires the user's local snapshot review before transmission.
            try AccessibilitySupport.rejectSecure(focused)
        }
        let requestGeneration = generation
        capturing = true
        defer { capturing = false }
        let contents = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard requestGeneration == generation else { throw LocalServiceError.cancelled }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw LocalServiceError.unsafeTarget("The foreground application changed before capture. Try sharing again.")
        }
        // Core Graphics explicitly returns windows in front-to-back order; SCShareableContent does not.
        let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidateIDs = ordered.compactMap { window -> CGWindowID? in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
        guard let window = candidateIDs.lazy.compactMap({ id in contents.windows.first { $0.windowID == id } }).first,
              window.owningApplication?.processID == app.processIdentifier,
              window.frame.width > 1, window.frame.height > 1 else {
            throw LocalServiceError.unavailable("The foreground application has no shareable window.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = true
        // Bound both dimensions for predictable memory use. Snapshot geometry records this scaling.
        let nativeScale = CGFloat(filter.pointPixelScale)
        let desired = CGSize(width: window.frame.width * nativeScale, height: window.frame.height * nativeScale)
        let scale = min(1, 2400 / max(desired.width, desired.height))
        configuration.width = max(1, Int((desired.width * scale).rounded()))
        configuration.height = max(1, Int((desired.height * scale).rounded()))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard requestGeneration == generation else { throw LocalServiceError.cancelled }
        guard CGPreflightScreenCaptureAccess() else { throw LocalServiceError.permission("Screen Recording permission was removed.") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw LocalServiceError.unsafeTarget("The foreground application changed during capture. The snapshot was discarded.")
        }
        let latestWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let latestWindow = latestWindows.first {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }
        guard (latestWindow?[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.windowID,
              let bounds = latestWindow?[kCGWindowBounds as String] as? NSDictionary,
              let currentFrame = CGRect(dictionaryRepresentation: bounds),
              currentFrame == window.frame else {
            throw LocalServiceError.unsafeTarget("The selected window moved, resized, or changed during capture. The snapshot was discarded.")
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw LocalServiceError.failed("The snapshot could not be encoded.")
        }
        let display = contents.displays.max { lhs, rhs in
            let left = lhs.frame.intersection(window.frame)
            let right = rhs.frame.intersection(window.frame)
            return (left.isNull ? 0 : left.width * left.height) < (right.isNull ? 0 : right.width * right.height)
        }
        return ContextSnapshot(id: UUID(), capturedAt: Date(), appName: app.localizedName ?? "Application",
                               bundleID: app.bundleIdentifier, windowTitle: window.title ?? "Untitled window",
                               windowID: window.windowID, displayID: display?.displayID ?? CGMainDisplayID(),
                               frame: window.frame, pixelSize: CGSize(width: image.width, height: image.height),
                               image: NSImage(cgImage: image, size: window.frame.size), pngData: png)
    }

    func selectedText() throws -> String? {
        guard AXIsProcessTrusted() else {
            throw LocalServiceError.permission("Accessibility is required to read selected text.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let focused = try AccessibilitySupport.focusedElement(pid: app.processIdentifier)
        try AccessibilitySupport.rejectSecure(focused)
        guard let text = AccessibilitySupport.attribute(kAXSelectedTextAttribute, of: focused) as? String else { return nil }
        return String(text.prefix(30_000))
    }
}
