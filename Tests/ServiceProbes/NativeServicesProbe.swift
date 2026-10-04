import AppKit
import Foundation

@main
struct DotsServicesProbe {
    @MainActor
    static func main() async throws {
        var passed = [String]()
        let permission = PermissionCoordinator().status
        let shortcuts = HotkeyService()
        do {
            try shortcuts.update(action: .conversation, binding: HotkeyBinding(keyCode: 49, modifiers: 0, label: "invalid"))
            fatalError("Unmodified key accepted")
        } catch { passed.append("Unmodified shortcut rejected before registration") }
        do {
            try shortcuts.update(action: .conversation, binding: HotkeyBinding(keyCode: 999, modifiers: 2048, label: "invalid"))
            fatalError("Invalid key accepted")
        } catch { passed.append("Out-of-range key code rejected") }
        let gateway = ActionGateway()
        gateway.cancel()
        do {
            _ = try await gateway.launch(bundleID: "com.example.dots.nonexistent-test-application")
            fatalError("Missing app reported success")
        } catch { passed.append("Unavailable application rejected without dispatch") }
        if !permission.screenCapture {
            do {
                _ = try await ContextService().captureForegroundWindow()
                fatalError("Capture continued without permission")
            } catch { passed.append("Screen snapshot refused when permission is missing") }
        }
        if !permission.accessibility {
            do {
                _ = try gateway.captureInsertionTarget()
                fatalError("Accessibility capture continued without permission")
            } catch { passed.append("Insertion destination refused when Accessibility is missing") }
        }
        if permission.microphone != "Allowed" || permission.speech != "Allowed" {
            let dictation = DictationService()
            do {
                try await dictation.start()
                fatalError("Dictation continued without permission")
            } catch { passed.append("Dictation refused without permission; microphone stayed inactive") }
            assert(!dictation.isActive)
        }
        let snapshot = ContextSnapshot(id: UUID(), capturedAt: Date(), appName: "Synthetic", bundleID: nil,
                                       windowTitle: "Synthetic", windowID: 0, displayID: 0,
                                       frame: CGRect(x: -500, y: 200, width: 1000, height: 600),
                                       pixelSize: CGSize(width: 2000, height: 1200),
                                       image: NSImage(size: CGSize(width: 1, height: 1)), pngData: Data())
        assert(snapshot.globalPoint(forImagePoint: CGPoint(x: 1200, y: 800)) == CGPoint(x: 100, y: 600))
        passed.append("Native snapshot pixel-to-global mapping, including negative display origin")
        let result: [String: Any] = ["checks": passed, "microphone": permission.microphone,
                                     "speech": permission.speech, "screenCapture": permission.screenCapture,
                                     "accessibility": permission.accessibility,
                                     "capturedPrivateContent": false, "requestedPermissions": false]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
