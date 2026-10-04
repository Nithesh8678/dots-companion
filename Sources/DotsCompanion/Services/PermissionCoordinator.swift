import AppKit
import AVFoundation
import ApplicationServices
import Speech

struct PermissionStatus {
    let microphone: String
    let speech: String
    let screenCapture: Bool
    let accessibility: Bool
}

/// Reading status never displays a permission prompt. Request methods are UI actions only.
@MainActor
final class PermissionCoordinator {
    var status: PermissionStatus {
        PermissionStatus(
            microphone: Self.microphoneDescription(AVCaptureDevice.authorizationStatus(for: .audio)),
            speech: Self.speechDescription(SFSpeechRecognizer.authorizationStatus()),
            screenCapture: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted()
        )
    }

    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func requestScreenCapture() -> Bool { CGRequestScreenCaptureAccess() }

    func openAccessibilitySettings() { openPrivacyPane("Privacy_Accessibility") }
    func openMicrophoneSettings() { openPrivacyPane("Privacy_Microphone") }
    func openSpeechSettings() { openPrivacyPane("Privacy_SpeechRecognition") }
    func openScreenCaptureSettings() { openPrivacyPane("Privacy_ScreenCapture") }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func microphoneDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    private static func speechDescription(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }
}
