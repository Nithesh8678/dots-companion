import AppKit

enum AnnotationOverlayKind: String, CaseIterable {
    case highlight, circle, arrow, underline, dimOutsideRegion, numberedStep, label
}

struct AnnotationOverlayCommand {
    let id = UUID()
    let contextID: UUID
    let displayID: CGDirectDisplayID
    /// Global AppKit points (origin at the bottom left), never screenshot pixels.
    let frame: CGRect
    let kind: AnnotationOverlayKind
    let duration: TimeInterval
    let text: String?
    let step: Int?

    init(contextID: UUID, displayID: CGDirectDisplayID, frame: CGRect, kind: AnnotationOverlayKind,
         duration: TimeInterval = 4, text: String? = nil, step: Int? = nil) {
        self.contextID = contextID; self.displayID = displayID; self.frame = frame; self.kind = kind
        self.duration = duration.isFinite ? min(max(duration, 0.2), 15) : 4
        self.text = text.map { String($0.prefix(100)) }; self.step = step
    }
}

/// Purely local, click-through annotation surfaces. No screen capture, inference, or coordinate
/// guessing happens here. The caller must establish the target against fresh shared context.
@MainActor
final class AnnotationService {
    private var commands: [UUID: AnnotationOverlayCommand] = [:]
    private var panels: [CGDirectDisplayID: AnnotationPanel] = [:]
    private var expirations: [UUID: Task<Void, Never>] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    var activeCount: Int { commands.count }

    func show(_ command: AnnotationOverlayCommand) throws {
        let values = [command.frame.minX, command.frame.minY, command.frame.width, command.frame.height]
        guard values.allSatisfy(\.isFinite), command.frame.width > 0, command.frame.height > 0 else {
            throw LocalServiceError.unsafeTarget("The annotation has no valid screen target.")
        }
        guard let screen = NSScreen.screens.first(where: { Self.displayID($0) == command.displayID }),
              !screen.frame.intersection(command.frame).isEmpty else {
            throw LocalServiceError.unsafeTarget("The annotation's display or target is no longer available.")
        }
        guard commands.count < 24 else {
            throw LocalServiceError.unavailable("Finish or clear the current annotations before adding more.")
        }
        // A new snapshot invalidates earlier geometry rather than mixing coordinates from two views.
        if let currentContext = commands.values.first?.contextID, currentContext != command.contextID { clear() }
        commands[command.id] = command
        installInvalidationObserversIfNeeded()
        refresh(displayID: command.displayID, screen: screen)
        expirations[command.id] = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(command.duration * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.remove(command.id)
        }
    }

    func clear(contextID: UUID) {
        let matching = commands.values.filter { $0.contextID == contextID }.map(\.id)
        for id in matching { remove(id) }
    }

    func clear() {
        for expiration in expirations.values { expiration.cancel() }
        expirations.removeAll(); commands.removeAll()
        for panel in panels.values { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        removeInvalidationObservers()
    }

    static func appKitRect(fromQuartz frame: CGRect) -> CGRect {
        // The menu-bar display is first in NSScreen.screens, including multi-monitor layouts.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func remove(_ id: UUID) {
        guard let command = commands.removeValue(forKey: id) else { return }
        expirations.removeValue(forKey: id)?.cancel()
        if commands.values.contains(where: { $0.displayID == command.displayID }),
           let screen = NSScreen.screens.first(where: { Self.displayID($0) == command.displayID }) {
            refresh(displayID: command.displayID, screen: screen)
        } else if let panel = panels.removeValue(forKey: command.displayID) {
            panel.orderOut(nil); panel.close()
        }
        if commands.isEmpty { removeInvalidationObservers() }
    }

    private func refresh(displayID: CGDirectDisplayID, screen: NSScreen) {
        let panel = panels[displayID] ?? AnnotationPanel(contentRect: screen.frame)
        panels[displayID] = panel
        panel.setFrame(screen.frame, display: false)
        let view: AnnotationCanvas
        if let existing = panel.contentView as? AnnotationCanvas { view = existing }
        else {
            view = AnnotationCanvas(frame: CGRect(origin: .zero, size: screen.frame.size))
            panel.contentView = view
        }
        view.screenOrigin = screen.frame.origin
        view.commands = commands.values.filter { $0.displayID == displayID }.sorted { $0.id.uuidString < $1.id.uuidString }
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    private func installInvalidationObserversIfNeeded() {
        guard workspaceObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if name == NSWorkspace.didActivateApplicationNotification,
                   let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
                MainActor.assumeIsolated { self?.clear() }
            }
            workspaceObservers.append(observer)
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
        // Stop displaying a stale cue as soon as the user scrolls, navigates by clicking, or moves a window.
        let mask: NSEvent.EventTypeMask = [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged]
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.clear() }
            return event
        }
    }

    private func removeInvalidationObservers() {
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        globalEventMonitor = nil; localEventMonitor = nil
    }
}

@MainActor
private final class AnnotationPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; ignoresMouseEvents = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        setAccessibilityLabel("Temporary screen annotation")
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class AnnotationCanvas: NSView {
    var commands: [AnnotationOverlayCommand] = []
    var screenOrigin: CGPoint = .zero
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        let accent = NSColor.systemTeal
        for command in commands {
            let rect = command.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
            context.saveGState()
            context.setStrokeColor(accent.cgColor); context.setLineWidth(3)
            context.setLineCap(.round); context.setLineJoin(.round)
            switch command.kind {
            case .highlight:
                context.setFillColor(accent.withAlphaComponent(0.12).cgColor)
                let path = CGPath(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerWidth: 8, cornerHeight: 8, transform: nil)
                context.addPath(path); context.drawPath(using: .fillStroke)
            case .circle:
                context.strokeEllipse(in: rect.insetBy(dx: -4, dy: -4))
            case .underline:
                context.move(to: CGPoint(x: rect.minX, y: rect.minY - 4)); context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 4)); context.strokePath()
            case .arrow:
                let start = CGPoint(x: rect.minX, y: rect.maxY), end = CGPoint(x: rect.maxX, y: rect.minY)
                context.move(to: start); context.addLine(to: end); context.strokePath()
                let angle = atan2(end.y - start.y, end.x - start.x), length: CGFloat = min(14, max(7, rect.width * 0.25))
                context.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
                context.addLine(to: end)
                context.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6))); context.strokePath()
            case .dimOutsideRegion:
                context.setFillColor(NSColor.black.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0.65 : 0.32).cgColor)
                context.addRect(bounds); context.addRect(rect.insetBy(dx: -4, dy: -4)); context.fillPath(using: .evenOdd)
                context.stroke(rect.insetBy(dx: -4, dy: -4))
            case .numberedStep:
                drawLabel(String(command.step ?? 1), near: rect, accent: accent, compact: true)
                context.stroke(rect.insetBy(dx: -3, dy: -3))
            case .label:
                drawLabel(command.text ?? "Here", near: rect, accent: accent, compact: false)
            }
            if command.kind != .label, let text = command.text, !text.isEmpty {
                drawLabel(text, near: rect, accent: accent, compact: false)
            }
            context.restoreGState()
        }
    }

    private func drawLabel(_ text: String, near target: CGRect, accent: NSColor, compact: Bool) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: compact ? 13 : 12, weight: .semibold),
                                                   .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attrs)
        let width = compact ? max(28, size.width + 16) : min(280, size.width + 20)
        let height: CGFloat = 28
        let x = min(max(8, target.minX), max(8, bounds.width - width - 8))
        let above = target.maxY + 9
        let y = above + height < bounds.maxY - 8 ? above : max(8, target.minY - height - 9)
        let labelRect = CGRect(x: x, y: y, width: width, height: height)
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        let path = NSBezierPath(roundedRect: labelRect, xRadius: compact ? 14 : 7, yRadius: compact ? 14 : 7)
        path.fill(); accent.setStroke(); path.lineWidth = 1.5; path.stroke()
        (text as NSString).draw(in: labelRect.insetBy(dx: compact ? 8 : 10, dy: 6), withAttributes: attrs)
    }
}
