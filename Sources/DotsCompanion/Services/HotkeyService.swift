import AppKit
import Carbon

enum HotkeyAction: UInt32, CaseIterable {
    case conversation = 1
    case typed = 2
    case dictation = 3
    case stop = 4

    var title: String {
        switch self {
        case .conversation: return "Conversation"
        case .typed: return "Type to companion"
        case .dictation: return "Dictation"
        case .stop: return "Stop local activity"
        }
    }
}

struct HotkeyBinding: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static let defaults: [HotkeyAction: HotkeyBinding] = [
        .conversation: .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥ Space"),
        .typed: .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "⌃ ⌥ Space"),
        .dictation: .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(shiftKey | optionKey), label: "⇧ ⌥ Space"),
        .stop: .init(keyCode: UInt32(kVK_ANSI_Period), modifiers: UInt32(controlKey | optionKey), label: "⌃ ⌥ .")
    ]
}

/// Carbon registered combinations need no Input Monitoring permission. Modifier-only gestures
/// are deliberately not installed. Registration errors are surfaced instead of taking a shortcut.
@MainActor
final class HotkeyService {
    var onEvent: ((HotkeyAction, Bool) -> Void)?
    private(set) var bindings: [HotkeyAction: HotkeyBinding] = [:]
    private(set) var recoveredStartupActions: [HotkeyAction] = []
    private var references: [HotkeyAction: EventHotKeyRef] = [:]
    private var registeredIDs: [HotkeyAction: UInt32] = [:]
    private var nextIdentifier: UInt32 = 1
    private var handler: EventHandlerRef?
    private var pressed = Set<HotkeyAction>()
    private var sleepObserver: NSObjectProtocol?
    private let signature: OSType = 0x44545343 // DTSC
    private let preferences: UserDefaults?

    /// A nil store permits isolated registration probes without touching user preferences.
    init(preferences: UserDefaults? = .standard) {
        self.preferences = preferences
    }

    func registerDefaults() throws {
        try installHandlerIfNeeded()
        var errors: [String] = []
        let configured = startupBindings()
        for action in HotkeyAction.allCases {
            guard let binding = configured[action] else { continue }
            do { try update(action: action, binding: binding) }
            catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw LocalServiceError.unavailable(errors.joined(separator: "\n")) }
    }

    /// Resolve persisted values without registering anything or writing preferences. Only
    /// structurally unsafe combinations recover to defaults; system/exclusive conflicts do not.
    func startupBindings() -> [HotkeyAction: HotkeyBinding] {
        recoveredStartupActions.removeAll()
        var configured: [HotkeyAction: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases {
            let prefix = "shortcut.\(action.rawValue)."
            let binding: HotkeyBinding
            if let defaults = preferences, defaults.object(forKey: prefix + "keyCode") != nil,
               let label = defaults.string(forKey: prefix + "label") {
                binding = HotkeyBinding(keyCode: UInt32(exactly: defaults.integer(forKey: prefix + "keyCode")) ?? .max,
                                        modifiers: UInt32(exactly: defaults.integer(forKey: prefix + "modifiers")) ?? .max, label: label)
            } else { binding = HotkeyBinding.defaults[action]! }
            do {
                try Self.validateBinding(binding)
                configured[action] = binding
            } catch {
                configured[action] = HotkeyBinding.defaults[action]
                recoveredStartupActions.append(action)
            }
        }
        return configured
    }

    static func validateBinding(_ binding: HotkeyBinding) throws {
        let allowed = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        guard binding.keyCode <= 127, binding.modifiers & ~allowed == 0,
              binding.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            throw LocalServiceError.unavailable("Use a key together with Option, Control, or Command. Modifier-only gestures are not enabled.")
        }
        let hasCommand = binding.modifiers & UInt32(cmdKey) != 0
        let hasControlOrOption = binding.modifiers & UInt32(controlKey | optionKey) != 0
        let functionKeys: Set<UInt32> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7,
            kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16,
            kVK_F17, kVK_F18, kVK_F19, kVK_F20].map { UInt32($0) }.reduce(into: Set()) { $0.insert($1) }
        guard !hasCommand || hasControlOrOption || functionKeys.contains(binding.keyCode) else {
            throw LocalServiceError.unavailable("Command-only and Command+Shift text shortcuts are reserved for the app you are using. Add Control or Option, or choose a function key, so editing and quit shortcuts keep working.")
        }
    }

    func update(action: HotkeyAction, binding: HotkeyBinding) throws {
        try Self.validateBinding(binding)
        guard !bindings.contains(where: { $0.key != action && $0.value.keyCode == binding.keyCode && $0.value.modifiers == binding.modifiers }) else {
            throw LocalServiceError.unavailable("That shortcut is already used by another companion action.")
        }
        guard !(try Self.systemReservedBindings()).contains(where: { $0.keyCode == binding.keyCode && $0.modifiers == binding.modifiers }) else {
            throw LocalServiceError.unavailable("\(binding.label) is reserved by an enabled macOS keyboard shortcut. Choose another combination or change that shortcut in System Settings.")
        }
        try installHandlerIfNeeded()
        if bindings[action]?.keyCode == binding.keyCode, bindings[action]?.modifiers == binding.modifiers { return }
        var newReference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: nextIdentifier)
        nextIdentifier &+= 1
        // Exclusive registrations reject competing exclusive owners. macOS does not expose a
        // complete inventory of other applications' nonexclusive hotkeys; see hotkey evidence.
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, identifier,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &newReference)
        guard status == noErr, let newReference else {
            throw LocalServiceError.unavailable("\(action.title): \(binding.label) could not be registered (\(status)). It may be used by macOS or another app. Choose another binding.")
        }
        if let existing = references[action] { UnregisterEventHotKey(existing) }
        references[action] = newReference
        registeredIDs[action] = identifier.id
        bindings[action] = binding
        pressed.remove(action)
        let prefix = "shortcut.\(action.rawValue)."
        preferences?.set(binding.keyCode, forKey: prefix + "keyCode")
        preferences?.set(binding.modifiers, forKey: prefix + "modifiers")
        preferences?.set(binding.label, forKey: prefix + "label")
    }

    func unregisterAll() {
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll()
        registeredIDs.removeAll()
        bindings.removeAll()
        pressed.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }

    static func systemReservedBindings() throws -> [HotkeyBinding] {
        var array: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&array)
        guard status == noErr, let array else {
            throw LocalServiceError.unavailable("macOS keyboard reservations could not be checked (\(status)). No new shortcut was registered.")
        }
        let values = array.takeRetainedValue() as NSArray
        return values.compactMap { value in
            guard let dictionary = value as? [String: Any],
                  (dictionary[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let keyCode = (dictionary[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                  let modifiers = (dictionary[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value else { return nil }
            return HotkeyBinding(keyCode: keyCode, modifiers: modifiers, label: "macOS shortcut")
        }
    }

    private func installHandlerIfNeeded() throws {
        guard handler == nil else { return }
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x44545343 else { return OSStatus(eventNotHandledErr) }
            let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            let registrationID = identifier.id
            Task { @MainActor [weak service] in service?.receive(identifier: registrationID, isPressed: isPressed) }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, events.count, &events,
                                          Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw LocalServiceError.failed("Global shortcut registration failed (\(status)).") }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for action in self.pressed { self.onEvent?(action, false) }
                self.pressed.removeAll()
            }
        }
    }

    private func receive(identifier: UInt32, isPressed: Bool) {
        guard let action = registeredIDs.first(where: { $0.value == identifier })?.key,
              references[action] != nil else { return }
        if isPressed {
            guard pressed.insert(action).inserted else { return }
        } else {
            guard pressed.remove(action) != nil else { return }
        }
        onEvent?(action, isPressed)
    }
}
