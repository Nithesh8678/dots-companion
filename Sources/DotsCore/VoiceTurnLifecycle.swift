import Foundation

public enum VoiceConversationState: String, Codable, Sendable {
    case idle, preparing, listening, thinking, speaking, error
}
public enum VoiceTurnTag: Sendable {}
public typealias VoiceTurnToken = Identifier<VoiceTurnTag>

/// Pure lifecycle used by the native local-voice controller. Callback identities are immutable;
/// old microphone, inference and playback callbacks cannot advance a replacement turn.
public struct VoiceTurnLifecycle: Sendable {
    public private(set) var state: VoiceConversationState = .idle
    public private(set) var isSessionActive = false
    public private(set) var token: VoiceTurnToken?
    private var wantsMicrophone = false
    private var inputSubmitted = false
    private var outputReady = false
    private var outputFinished = false

    public init() {}

    @discardableResult public mutating func begin(voiceSession: Bool, microphone: Bool) -> VoiceTurnToken {
        let next = VoiceTurnToken()
        token = next; isSessionActive = voiceSession; wantsMicrophone = microphone
        inputSubmitted = false; outputReady = false; outputFinished = false
        state = microphone ? .preparing : .thinking
        return next
    }

    public func accepts(_ callback: VoiceTurnToken) -> Bool { token == callback }

    @discardableResult public mutating func microphoneStarted(_ callback: VoiceTurnToken) -> Bool {
        guard accepts(callback), wantsMicrophone, state == .preparing, !inputSubmitted, !outputFinished else { return false }
        state = .listening; return true
    }

    @discardableResult public mutating func finishInput(_ callback: VoiceTurnToken) -> Bool {
        guard accepts(callback), state == .listening, !inputSubmitted else { return false }
        state = .thinking; return true
    }

    @discardableResult public mutating func commitInput(_ callback: VoiceTurnToken) -> Bool {
        guard accepts(callback), !inputSubmitted, [.preparing, .listening, .thinking].contains(state) else { return false }
        inputSubmitted = true; state = .thinking; return true
    }

    @discardableResult public mutating func responseReady(_ callback: VoiceTurnToken) -> Bool {
        guard accepts(callback), inputSubmitted, !outputReady, state == .thinking else { return false }
        outputReady = true; return true
    }

    @discardableResult public mutating func speechStarted(_ callback: VoiceTurnToken) -> Bool {
        guard accepts(callback), outputReady, !outputFinished, state == .thinking else { return false }
        state = .speaking; return true
    }

    /// A typed-only turn has no microphone continuation. Voice sessions require the caller's
    /// observed playback completion and a fresh microphone start before returning to listening.
    @discardableResult public mutating func finishOutput(_ callback: VoiceTurnToken) -> Bool {
        guard accepts(callback), outputReady, !outputFinished, [.thinking, .speaking].contains(state) else { return false }
        outputFinished = true
        if isSessionActive { state = .preparing }
        else { state = .idle; token = nil }
        return true
    }

    public func mayResumeMicrophone(after callback: VoiceTurnToken) -> Bool {
        accepts(callback) && isSessionActive && outputFinished && state == .preparing
    }

    @discardableResult public mutating func fail(_ callback: VoiceTurnToken) -> Bool {
        guard accepts(callback) else { return false }
        token = nil; isSessionActive = false; state = .error
        return true
    }

    public mutating func stop() {
        token = nil; isSessionActive = false; state = .idle
        wantsMicrophone = false; inputSubmitted = false; outputReady = false; outputFinished = false
    }
}
