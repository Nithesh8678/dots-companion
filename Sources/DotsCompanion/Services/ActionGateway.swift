import AppKit
import ApplicationServices

struct InsertionTarget {
    let id: UUID
    let pid: pid_t
    let appName: String
    let capturedAt: Date
    fileprivate let element: AXUIElement
    fileprivate let originalValue: String
    fileprivate let selection: CFRange
    fileprivate let generation: UInt64
}

struct ActionResult {
    let id: UUID
    let verified: Bool
    let summary: String
}

/// Only typed, bounded operations are exposed. There is no shell or arbitrary automation path.
@MainActor
final class ActionGateway {
    private var generation: UInt64 = 0
    private var consumedTargets = Set<UUID>()

    func cancel() { generation &+= 1 }

    func captureInsertionTarget() throws -> InsertionTarget {
        guard AXIsProcessTrusted() else {
            throw LocalServiceError.permission("Allow Accessibility to verify the destination field. You can also use Copy.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw LocalServiceError.unsafeTarget("Focus an editable field in another application, then use the dictation shortcut.")
        }
        let element = try AccessibilitySupport.focusedElement(pid: app.processIdentifier)
        try AccessibilitySupport.rejectSecure(element)
        let role = AccessibilitySupport.attribute(kAXRoleAttribute, of: element) as? String ?? ""
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            throw LocalServiceError.unsafeTarget("The focused control is not a supported editable text field. Use Copy instead.")
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue,
              let value = AccessibilitySupport.attribute(kAXValueAttribute, of: element) as? String,
              value.utf16.count <= 2_000_000,
              let selection = AccessibilitySupport.selectedRange(element),
              selection.location >= 0, selection.length >= 0,
              selection.location <= value.utf16.count,
              selection.length <= value.utf16.count - selection.location else {
            throw LocalServiceError.unavailable("This editor cannot verify direct insertion. Use Copy to paste the reviewed text yourself.")
        }
        return InsertionTarget(id: UUID(), pid: app.processIdentifier, appName: app.localizedName ?? "Application",
                               capturedAt: Date(), element: element, originalValue: value,
                               selection: selection, generation: generation)
    }

    func insert(text: String, into target: InsertionTarget) throws -> ActionResult {
        guard target.generation == generation else { throw LocalServiceError.cancelled }
        guard !consumedTargets.contains(target.id) else {
            throw LocalServiceError.unsafeTarget("This insertion has already been dispatched. It will not be repeated.")
        }
        guard !text.isEmpty, text.utf16.count <= 500_000 else {
            throw LocalServiceError.unavailable("There is no text to insert, or it is too large for direct insertion.")
        }
        guard Date().timeIntervalSince(target.capturedAt) < 300 else {
            throw LocalServiceError.unsafeTarget("The destination expired. Focus the field and start again.")
        }
        guard AXIsProcessTrusted() else { throw LocalServiceError.permission("Accessibility permission is no longer available.") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            throw LocalServiceError.unsafeTarget("The foreground application changed. Text was not inserted.")
        }
        let focused = try AccessibilitySupport.focusedElement(pid: target.pid)
        guard CFEqual(focused, target.element) else {
            throw LocalServiceError.unsafeTarget("The focused field changed. Text was not inserted.")
        }
        try AccessibilitySupport.rejectSecure(focused)
        guard let currentRange = AccessibilitySupport.selectedRange(focused),
              currentRange.location == target.selection.location, currentRange.length == target.selection.length,
              AccessibilitySupport.attribute(kAXValueAttribute, of: focused) as? String == target.originalValue else {
            throw LocalServiceError.unsafeTarget("The text or selection changed. Text was not inserted.")
        }
        guard target.generation == generation else { throw LocalServiceError.cancelled }
        let expected = (target.originalValue as NSString).replacingCharacters(
            in: NSRange(location: target.selection.location, length: target.selection.length), with: text)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              CFEqual(try AccessibilitySupport.focusedElement(pid: target.pid), focused) else {
            throw LocalServiceError.unsafeTarget("Focus changed during verification. Text was not inserted.")
        }
        consumedTargets.insert(target.id)
        // Bound deduplication storage by invalidating every old destination before discarding IDs.
        if consumedTargets.count > 512 { generation &+= 1; consumedTargets = [target.id] }
        let error = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFString)
        guard error == .success else { throw LocalServiceError.failed("The editor refused text insertion (Accessibility \(error.rawValue)).") }
        let observed = AccessibilitySupport.attribute(kAXValueAttribute, of: focused) as? String
        let verified = observed == expected
        return ActionResult(id: target.id, verified: verified,
                            summary: verified ? "Inserted and verified in \(target.appName)." : "Insertion was dispatched, but the editor did not expose a matching result. Check the field; it will not be retried.")
    }

    func launch(bundleID: String) async throws -> ActionResult {
        let capturedGeneration = generation
        guard !bundleID.isEmpty, bundleID.count < 256,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw LocalServiceError.unavailable("The requested application is not installed.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard capturedGeneration == generation else { throw LocalServiceError.cancelled }
        let application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        guard capturedGeneration == generation else { throw LocalServiceError.cancelled }
        let verified = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier == application.processIdentifier && !$0.isTerminated }
        return ActionResult(id: UUID(), verified: verified,
                            summary: verified ? "\(application.localizedName ?? bundleID) is running." : "Launch was requested; application presence could not be verified.")
    }
}
