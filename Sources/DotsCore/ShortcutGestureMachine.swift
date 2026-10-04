import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let command = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
}
public enum ShortcutGestureAction: Equatable, Sendable {
    case beginHold, endHold, cancelHold, toggleConversation, typedSummon, stop
}
public enum ShortcutKey: Equatable, Sendable { case space, escape, other }
public enum ShortcutInput: Equatable, Sendable {
    case modifiers(ShortcutModifiers, time: TimeInterval)
    case keyDown(ShortcutKey, modifiers: ShortcutModifiers, isRepeat: Bool, time: TimeInterval)
    case keyUp(ShortcutKey, time: TimeInterval)
    case holdThresholdReached(time: TimeInterval)
    case reset
}

/// Pure gesture recognition. A native adapter remains responsible for registering a regular
/// shortcut and handling conflicts. Modifier-only observation is opt-in.
public struct ShortcutGestureMachine: Sendable {
    public let doubleTapInterval: TimeInterval
    public let maximumTapDuration: TimeInterval
    public let modifierGesturesEnabled: Bool
    public let toggleModifiers: ShortcutModifiers
    public let holdActivationDelay: TimeInterval
    private var currentModifiers: ShortcutModifiers = []
    private var controlPressedAt: TimeInterval?
    private var firstControlTap: TimeInterval?
    private var controlTapContaminated = false
    private var holdActive = false
    private var holdPendingAt: TimeInterval?
    private var holdContaminated = false
    private var spaceDown = false
    private var lastTimestamp: TimeInterval?

    public init(modifierGesturesEnabled: Bool = false, toggleModifiers: ShortcutModifiers = [.option],
                doubleTapInterval: TimeInterval = 0.35, maximumTapDuration: TimeInterval = 0.25,
                holdActivationDelay: TimeInterval = 0.12) {
        self.modifierGesturesEnabled = modifierGesturesEnabled
        self.toggleModifiers = toggleModifiers
        self.doubleTapInterval = max(0.05, doubleTapInterval)
        self.maximumTapDuration = max(0.05, maximumTapDuration)
        self.holdActivationDelay = max(0.05, holdActivationDelay)
    }

    public mutating func handle(_ input: ShortcutInput) -> [ShortcutGestureAction] {
        switch input {
        case .reset:
            let wasHolding = holdActive
            resetState()
            return wasHolding ? [.cancelHold] : []
        case .holdThresholdReached(let time):
            guard acceptTimestamp(time), let pending = holdPendingAt, !holdContaminated,
                  currentModifiers == [.control, .option], time - pending >= holdActivationDelay else { return [] }
            holdPendingAt = nil; holdActive = true
            return [.beginHold]
        case .keyDown(let key, let modifiers, let isRepeat, let time):
            guard acceptTimestamp(time) else { return [] }
            controlTapContaminated = true; firstControlTap = nil
            holdPendingAt = nil; holdContaminated = true
            let cancelledHold = holdActive
            holdActive = false
            if key == .escape, !isRepeat {
                resetState()
                return cancelledHold ? [.cancelHold, .stop] : [.stop]
            }
            guard key == .space else { return cancelledHold ? [.cancelHold] : [] }
            defer { spaceDown = true }
            guard !isRepeat, !spaceDown, modifiers == toggleModifiers else { return cancelledHold ? [.cancelHold] : [] }
            return cancelledHold ? [.cancelHold, .toggleConversation] : [.toggleConversation]
        case .keyUp(let key, let time):
            guard acceptTimestamp(time) else { return [] }
            if key == .space { spaceDown = false }
            return []
        case .modifiers(let modifiers, let time):
            guard acceptTimestamp(time) else { return [] }
            defer { currentModifiers = modifiers }
            guard modifierGesturesEnabled else { return [] }
            var actions: [ShortcutGestureAction] = []
            let holdChord: ShortcutModifiers = [.control, .option]
            if holdActive && modifiers != holdChord {
                holdActive = false
                actions.append(modifiers.subtracting(holdChord).isEmpty ? .endHold : .cancelHold)
            }
            if modifiers != holdChord { holdPendingAt = nil }
            if !modifiers.subtracting(holdChord).isEmpty { holdContaminated = true }
            if modifiers == holdChord && currentModifiers != holdChord {
                controlTapContaminated = true; firstControlTap = nil
                if !holdContaminated { holdPendingAt = time }
            }
            if modifiers == [.control], !currentModifiers.contains(.control) {
                controlPressedAt = time; controlTapContaminated = false
            } else if modifiers != [.control] && modifiers.contains(.control) {
                controlTapContaminated = true; firstControlTap = nil
            }
            if currentModifiers.contains(.control), !modifiers.contains(.control), let pressed = controlPressedAt {
                controlPressedAt = nil
                if modifiers.isEmpty, !controlTapContaminated, time - pressed <= maximumTapDuration {
                    if let firstTap = firstControlTap, time - firstTap <= doubleTapInterval {
                        firstControlTap = nil; actions.append(.typedSummon)
                    } else { firstControlTap = time }
                } else { firstControlTap = nil }
            }
            if modifiers.isEmpty { holdContaminated = false }
            return actions
        }
    }

    private mutating func acceptTimestamp(_ time: TimeInterval) -> Bool {
        guard time.isFinite, lastTimestamp.map({ time >= $0 }) ?? true else { return false }
        lastTimestamp = time; return true
    }
    private mutating func resetState() {
        currentModifiers = []; controlPressedAt = nil; firstControlTap = nil
        controlTapContaminated = false; holdActive = false; spaceDown = false; lastTimestamp = nil
        holdPendingAt = nil; holdContaminated = false
    }
}
