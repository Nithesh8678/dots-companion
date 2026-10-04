import Foundation

/// A UUID whose type prevents a context, turn or task from being used interchangeably.
public struct Identifier<Tag>: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }
}
public enum SessionTag: Sendable {}
public enum TurnTag: Sendable {}
public enum TaskTag: Sendable {}
public enum ContextTag: Sendable {}
public enum ActionTag: Sendable {}
public typealias SessionID = Identifier<SessionTag>
public typealias TurnID = Identifier<TurnTag>
public typealias TaskID = Identifier<TaskTag>
public typealias ContextID = Identifier<ContextTag>
public typealias ActionID = Identifier<ActionTag>

public struct BackendCapabilities: OptionSet, Codable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let openHost = Self(rawValue: 1 << 0)
    public static let voiceEvents = Self(rawValue: 1 << 1)
    public static let transcripts = Self(rawValue: 1 << 2)
    public static let screenContext = Self(rawValue: 1 << 3)
    public static let localActions = Self(rawValue: 1 << 4)
    public static let taskEvents = Self(rawValue: 1 << 5)
    public static let remoteCancellation = Self(rawValue: 1 << 6)
    public static let persistentMemory = Self(rawValue: 1 << 7)
    public static let hostBridge: Self = [.openHost]
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case dormant, appearing, openingHost, hostOpen, listening, thinking, speaking
    case acting, waitingForUser, completed, permissionNeeded, offline, error, cancelled
}

public enum SessionEvent: Equatable, Sendable {
    case appeared, hostOpening, hostOpened, listeningStarted, inputCommitted
    case speechStarted, speechFinished, completed, offline, cancellationAcknowledged
    case transcript(String), waitingForUser(String), permissionNeeded(String), failed(String)
    case actionStarted, actionFinished
}

public struct SessionEventEnvelope: Sendable {
    public let sessionID: SessionID
    public let turnID: TurnID?
    public let generation: UInt64
    public let event: SessionEvent
    public init(sessionID: SessionID, turnID: TurnID?, generation: UInt64, event: SessionEvent) {
        self.sessionID = sessionID; self.turnID = turnID
        self.generation = generation; self.event = event
    }
}

public enum EventDisposition: Equatable, Sendable {
    case applied, staleSession, staleTurn, staleGeneration, unsupportedCapability, invalidTransition
}

public struct CancellationTicket: Equatable, Sendable {
    public let sessionID: SessionID?
    public let turnID: TurnID?
    public let generation: UInt64
    public let remoteAcknowledgementRequired: Bool
}

/// The voice surface is separate from TaskCoordinator: ending a call never invents a task stop.
/// Effects are deliberately left to the owner, which must stop local capture/playback immediately.
public struct SessionStateMachine: Sendable {
    public let capabilities: BackendCapabilities
    public private(set) var sessionID: SessionID?
    public private(set) var turnID: TurnID?
    public private(set) var generation: UInt64 = 0
    public private(set) var state: SessionState = .dormant
    public private(set) var transcript: String = ""
    public private(set) var statusMessage: String = ""
    public private(set) var remoteCancellationPending = false
    public private(set) var isVisible = false

    public init(capabilities: BackendCapabilities) { self.capabilities = capabilities }

    @discardableResult public mutating func beginSession() -> SessionID {
        generation &+= 1
        let identifier = SessionID()
        sessionID = identifier; turnID = nil; state = .appearing
        transcript = ""; statusMessage = ""; remoteCancellationPending = false; isVisible = true
        return identifier
    }

    @discardableResult public mutating func startTurn() -> TurnID? {
        guard sessionID != nil, state != .dormant, state != .cancelled else { return nil }
        generation &+= 1
        let identifier = TurnID()
        turnID = identifier; transcript = ""; statusMessage = ""
        state = .appearing; isVisible = true
        return identifier
    }

    /// Hide is purely visual; it must not claim that a call or task has ended.
    public mutating func hide() { isVisible = false }
    public mutating func show() { isVisible = true }

    @discardableResult public mutating func cancel() -> CancellationTicket {
        generation &+= 1
        let previousTurn = turnID
        turnID = nil
        remoteCancellationPending = sessionID != nil && capabilities.contains(.remoteCancellation)
        state = .cancelled
        statusMessage = remoteCancellationPending ? "Stopping…" : "Local activity stopped"
        return CancellationTicket(sessionID: sessionID, turnID: previousTurn, generation: generation,
                                  remoteAcknowledgementRequired: remoteCancellationPending)
    }

    @discardableResult public mutating func apply(_ envelope: SessionEventEnvelope) -> EventDisposition {
        guard let currentSession = sessionID, envelope.sessionID == currentSession else { return .staleSession }
        guard envelope.generation == generation else { return .staleGeneration }
        if envelope.event == .cancellationAcknowledged {
            guard capabilities.contains(.remoteCancellation) else { return .unsupportedCapability }
            guard state == .cancelled, remoteCancellationPending else { return .invalidTransition }
            remoteCancellationPending = false; statusMessage = "Call stop acknowledged"
            return .applied
        }
        guard state != .cancelled, state != .dormant else { return .invalidTransition }
        guard envelope.turnID == turnID else { return .staleTurn }

        switch envelope.event {
        case .appeared:
            guard state == .appearing else { return .invalidTransition }
            state = .waitingForUser
        case .hostOpening:
            guard capabilities.contains(.openHost) else { return .unsupportedCapability }
            state = .openingHost; statusMessage = "Opening ChatGPT"
        case .hostOpened:
            guard capabilities.contains(.openHost) else { return .unsupportedCapability }
            guard state == .openingHost else { return .invalidTransition }
            state = .hostOpen; statusMessage = "ChatGPT opened; call state is managed there"
        case .listeningStarted:
            guard capabilities.contains(.voiceEvents) else { return .unsupportedCapability }
            guard turnID != nil else { return .invalidTransition }
            state = .listening
        case .inputCommitted:
            guard capabilities.contains(.voiceEvents) else { return .unsupportedCapability }
            guard turnID != nil, [.listening, .waitingForUser, .appearing].contains(state) else { return .invalidTransition }
            state = .thinking
        case .speechStarted:
            guard capabilities.contains(.voiceEvents) else { return .unsupportedCapability }
            guard turnID != nil, [.thinking, .speaking].contains(state) else { return .invalidTransition }
            state = .speaking
        case .speechFinished:
            guard capabilities.contains(.voiceEvents) else { return .unsupportedCapability }
            guard state == .speaking else { return .invalidTransition }
            state = .waitingForUser
        case .transcript(let value):
            guard capabilities.contains(.transcripts) else { return .unsupportedCapability }
            guard turnID != nil else { return .invalidTransition }
            transcript = String(value.prefix(16_384))
        case .actionStarted:
            guard capabilities.contains(.localActions) else { return .unsupportedCapability }
            state = .acting
        case .actionFinished:
            guard capabilities.contains(.localActions) else { return .unsupportedCapability }
            guard state == .acting else { return .invalidTransition }
            state = .waitingForUser
        case .completed:
            guard !capabilities.intersection([.voiceEvents, .localActions]).isEmpty else { return .unsupportedCapability }
            state = .completed
        case .waitingForUser(let message): state = .waitingForUser; statusMessage = String(message.prefix(1_024))
        case .permissionNeeded(let message): state = .permissionNeeded; statusMessage = String(message.prefix(1_024))
        case .offline: state = .offline; statusMessage = "Offline"
        case .failed(let message): state = .error; statusMessage = String(message.prefix(1_024))
        case .cancellationAcknowledged: return .invalidTransition
        }
        return .applied
    }
}
