import Foundation

public struct FocusSnapshot: Equatable, Codable, Sendable {
    public let processID: Int32
    /// Stable identifier scoped to the AX element, not merely its role or title.
    public let fieldID: String?
    public let isEditable: Bool
    public let isSecure: Bool
    public init(processID: Int32, fieldID: String?, isEditable: Bool, isSecure: Bool) {
        self.processID = processID; self.fieldID = fieldID
        self.isEditable = isEditable; self.isSecure = isSecure
    }
}

public enum ActionKind: String, Codable, Sendable {
    case insertText, activateControl, launchApplication, selectFile
}
public struct ActionRequest: Codable, Sendable {
    public let id: ActionID
    public let kind: ActionKind
    public let generation: UInt64
    public let idempotencyKey: String
    public let intendedFocus: FocusSnapshot?
    public let contextID: ContextID?
    public let usesScreenCoordinates: Bool
    public let requiresConfirmation: Bool
    public let confirmed: Bool
    public init(id: ActionID = ActionID(), kind: ActionKind, generation: UInt64, idempotencyKey: String,
                intendedFocus: FocusSnapshot? = nil, contextID: ContextID? = nil,
                usesScreenCoordinates: Bool = false, requiresConfirmation: Bool = false, confirmed: Bool = false) {
        self.id = id; self.kind = kind; self.generation = generation; self.idempotencyKey = idempotencyKey
        self.intendedFocus = intendedFocus; self.contextID = contextID; self.usesScreenCoordinates = usesScreenCoordinates
        self.requiresConfirmation = requiresConfirmation; self.confirmed = confirmed
    }
}
public enum ActionRefusal: String, Error, Equatable, Sendable {
    case cancelled, permissionMissing, confirmationRequired, duplicate, invalidIdempotencyKey
    case targetMissing, applicationChanged, fieldChanged, secureField, notEditable
    case contextMissing, contextChanged, staleContext, capacityReached
}
public enum ActionDecision: Equatable, Sendable {
    case dispatch(ActionID)
    case refused(ActionRefusal)
}

/// Pure preflight plus reservation. Call again immediately before an effect if preflight and
/// effect are separated by an await, using `validate` rather than making a second reservation.
/// It records no text, screenshots, or credentials. Never retry a dispatched effect blindly.
public struct ActionGate: Sendable {
    private var dispatchedKeys: Set<String> = []
    private let capacity: Int
    public init(capacity: Int = 512) { self.capacity = max(1, capacity) }
    public var reservationCount: Int { dispatchedKeys.count }

    public func validate(_ request: ActionRequest, currentGeneration: UInt64,
                         dispatchEnabled: Bool = true, permissionGranted: Bool,
                         currentFocus: FocusSnapshot?, context: ContextSnapshot? = nil,
                         currentContextRevision: UInt64 = 0, currentWindowID: String? = nil, now: Date = Date(),
                         maxContextAge: TimeInterval = 3) -> ActionRefusal? {
        guard dispatchEnabled, request.generation == currentGeneration else { return .cancelled }
        guard permissionGranted else { return .permissionMissing }
        guard !request.requiresConfirmation || request.confirmed else { return .confirmationRequired }
        guard !request.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.idempotencyKey.utf8.count <= 256 else { return .invalidIdempotencyKey }
        if request.kind != .launchApplication {
            guard let target = request.intendedFocus, let actual = currentFocus else { return .targetMissing }
            guard target.processID == actual.processID else { return .applicationChanged }
            guard let fieldID = target.fieldID, !fieldID.isEmpty, actual.fieldID == fieldID else { return .fieldChanged }
            guard !target.isSecure, !actual.isSecure else { return .secureField }
            if request.kind == .insertText {
                guard target.isEditable, actual.isEditable else { return .notEditable }
            }
        }
        if request.usesScreenCoordinates {
            guard let identifier = request.contextID, let snapshot = context,
                  let actual = currentFocus, let windowID = currentWindowID else { return .contextMissing }
            guard identifier == snapshot.id else { return .contextChanged }
            guard snapshot.isFresh(now: now, maxAge: maxContextAge, currentRevision: currentContextRevision,
                                   processID: actual.processID, windowID: windowID) else { return .staleContext }
        }
        return nil
    }

    public mutating func authorize(_ request: ActionRequest, currentGeneration: UInt64,
                                   dispatchEnabled: Bool = true, permissionGranted: Bool,
                                   currentFocus: FocusSnapshot?, context: ContextSnapshot? = nil,
                                   currentContextRevision: UInt64 = 0, currentWindowID: String? = nil, now: Date = Date(),
                                   maxContextAge: TimeInterval = 3) -> ActionDecision {
        if let refusal = validate(request, currentGeneration: currentGeneration, dispatchEnabled: dispatchEnabled,
                                  permissionGranted: permissionGranted, currentFocus: currentFocus, context: context,
                                  currentContextRevision: currentContextRevision, currentWindowID: currentWindowID,
                                  now: now, maxContextAge: maxContextAge) {
            return .refused(refusal)
        }
        guard !dispatchedKeys.contains(request.idempotencyKey) else { return .refused(.duplicate) }
        // Do not evict deduplication entries: eviction would permit an old non-idempotent retry.
        guard dispatchedKeys.count < capacity else { return .refused(.capacityReached) }
        dispatchedKeys.insert(request.idempotencyKey)
        return .dispatch(request.id)
    }
}
