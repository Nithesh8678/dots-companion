import AppKit
import AVFoundation
import Speech
import Accelerate

/// Explicit, on-device-only dictation. No audio is retained or sent to an assistant backend.
@MainActor
final class DictationService {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var isActive = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var generation: UInt64 = 0
    private var tapInstalled = false
    private var finishing = false
    private var permissionTimer: Timer?
    private var finishTimer: Timer?
    private var routeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var startedAt = Date()

    func start(localeIdentifier: String = Locale.current.identifier) async throws {
        guard !isActive else { throw LocalServiceError.unavailable("Dictation is already active.") }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw LocalServiceError.permission("Allow Microphone in Settings before starting dictation.")
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw LocalServiceError.permission("Allow Speech Recognition in Settings before starting dictation.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw LocalServiceError.unavailable("Speech recognition is not available for \(localeIdentifier) on this Mac.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw LocalServiceError.unavailable("On-device dictation is not available for \(localeIdentifier). Choose a supported language; audio has not been sent to a server.")
        }
        generation &+= 1
        let currentGeneration = generation
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.request = nil
            self.recognizer = nil
            throw LocalServiceError.unavailable("No usable microphone was found. Connect an input device and try again.")
        }
        isActive = true
        finishing = false
        startedAt = Date()
        let meter = DictationLevelMeter()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, request] buffer, _ in
            request.append(buffer)
            guard let level = meter.levelIfDue(buffer) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.generation == currentGeneration, !self.finishing else { return }
                self.onLevel?(level)
            }
        }
        tapInstalled = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.generation == currentGeneration else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.cleanup(cancelRecognition: false)
                        self.onFinal?(text)
                        return
                    }
                    self.onPartial?(text)
                }
                if let error {
                    self.cleanup(cancelRecognition: true)
                    self.onError?("Dictation stopped: \(error.localizedDescription)")
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            cleanup(cancelRecognition: true)
            throw LocalServiceError.failed("The microphone could not start: \(error.localizedDescription)")
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.generation == currentGeneration else { return }
                if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized || SFSpeechRecognizer.authorizationStatus() != .authorized {
                    self.cancel()
                    self.onError?("Microphone or Speech Recognition permission was removed. Dictation stopped.")
                } else if Date().timeIntervalSince(self.startedAt) >= 120, !self.finishing {
                    self.finish()
                }
            }
        }
        routeObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.generation == currentGeneration else { return }
                self.cancel()
                self.onError?("The audio device changed. Dictation stopped; start again with the new device.")
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    /// Stops the microphone immediately, then gives the recognizer four seconds to finalize.
    func finish() {
        guard isActive, !finishing else { return }
        finishing = true
        stopInput()
        request?.endAudio()
        onLevel?(0)
        let currentGeneration = generation
        finishTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.generation == currentGeneration else { return }
                self.cancel()
                self.onError?("The speech recognizer did not finalize. Review the partial transcript; nothing was inserted.")
            }
        }
    }

    func cancel() {
        generation &+= 1
        cleanup(cancelRecognition: true)
    }

    private func stopInput() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    private func cleanup(cancelRecognition: Bool) {
        isActive = false
        finishing = false
        stopInput()
        request?.endAudio()
        if cancelRecognition { recognitionTask?.cancel() }
        recognitionTask = nil
        request = nil
        recognizer = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        finishTimer?.invalidate()
        finishTimer = nil
        if let observer = routeObserver { NotificationCenter.default.removeObserver(observer) }
        routeObserver = nil
        if let observer = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObserver = nil
        onLevel?(0)
    }
}

/// The audio callback does bounded work and schedules at most 15 meter updates per second.
private final class DictationLevelMeter: @unchecked Sendable {
    private var lastTimestamp: TimeInterval = 0
    func levelIfDue(_ buffer: AVAudioPCMBuffer) -> Float? {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTimestamp >= 1.0 / 15.0,
              let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        lastTimestamp = now
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
        return min(1, max(0, rms * 9))
    }
}
