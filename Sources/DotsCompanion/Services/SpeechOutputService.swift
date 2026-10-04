import AppKit
import AVFoundation

/// Optional local system speech. It has no relationship to a ChatGPT dot's voice or call.
/// Speaking starts only when AVSpeechSynthesizer confirms it; no synthetic energy is emitted.
@MainActor
final class SpeechOutputService: NSObject, AVSpeechSynthesizerDelegate {
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancelled: (() -> Void)?
    var onWillSpeakRange: ((NSRange) -> Void)?
    private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var sleepObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, voiceIdentifier: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        stop()
        let boundedText = String(text.prefix(16_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !boundedText.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: boundedText)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
        if let voiceIdentifier { utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) }
        activeUtterance = utterance
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        let hadUtterance = activeUtterance != nil
        // Retire the identity first: a late start/finish callback cannot revive old speech UI.
        activeUtterance = nil
        _ = synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        removeObserver()
        if hadUtterance { onCancelled?() }
    }

    private func removeObserver() {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.isSpeaking = true
            self.onStart?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.isSpeaking = false
            self.removeObserver()
            self.onFinish?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.isSpeaking = false
            self.removeObserver()
            self.onCancelled?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.onWillSpeakRange?(characterRange)
        }
    }
}
