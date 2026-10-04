// Standalone cross-process Carbon probe. No input is synthesized and no preferences are saved.
import AppKit
import Carbon
import Foundation

private let probeModifiers = UInt32(controlKey | optionKey | cmdKey)

@main
struct HotkeyConflictProbe {
    @MainActor
    static func main() throws {
        let safetyChecks = try verifyBindingSafety()
        if CommandLine.arguments.contains("--safety-only") {
            let data = try JSONSerialization.data(withJSONObject: ["checks": safetyChecks, "preferencesWritten": false, "syntheticKeyEvents": 0], options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        if CommandLine.arguments.contains("--holder") {
            try holdExclusiveBinding()
            return
        }
        if CommandLine.arguments.contains("--try-exclusive") {
            let status = tryExclusiveF18()
            writeLine(String(status))
            return
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let holder = Process()
        let holderInput = Pipe()
        let holderOutput = Pipe()
        holder.executableURL = executable
        holder.arguments = ["--holder"]
        holder.standardInput = holderInput
        holder.standardOutput = holderOutput
        try holder.run()
        defer {
            if holder.isRunning { try? holderInput.fileHandleForWriting.write(contentsOf: Data([10])) }
            holderInput.fileHandleForWriting.closeFile()
            if holder.isRunning { holder.waitUntilExit() }
        }
        let ready = String(decoding: holderOutput.fileHandleForReading.readData(ofLength: 6), as: UTF8.self)
        guard ready == "READY\n" else {
            throw LocalServiceError.unavailable("The temporary F19 binding was not free or could not be registered. No shortcut was overridden. Holder response: \(ready)")
        }
        guard holder.isRunning else { throw LocalServiceError.failed("The holder exited before conflict verification.") }
        let service = HotkeyService(preferences: nil)
        defer { service.unregisterAll() }
        let good = HotkeyBinding(keyCode: UInt32(kVK_F18), modifiers: probeModifiers, label: "⌃⌥⌘ F18")
        let conflict = HotkeyBinding(keyCode: UInt32(kVK_F19), modifiers: probeModifiers, label: "⌃⌥⌘ F19")
        try service.update(action: .conversation, binding: good)
        var commandRejected = false
        do { try service.update(action: .conversation, binding: HotkeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey), label: "⌘ A")) }
        catch { commandRejected = true }
        guard commandRejected, service.bindings[.conversation] == good else {
            throw LocalServiceError.failed("A rejected Command+A update replaced the existing binding.")
        }
        guard try runExclusiveProbe(executable) != noErr else {
            throw LocalServiceError.failed("The original F18 registration was lost after a rejected Command+A update.")
        }
        var refused = false
        var refusal = ""
        do { try service.update(action: .conversation, binding: conflict) }
        catch { refused = true; refusal = error.localizedDescription }
        guard refused else { throw LocalServiceError.failed("The exclusive cross-process binding was not refused.") }
        guard service.bindings[.conversation] == good else { throw LocalServiceError.failed("The previous working binding changed after a failed update.") }
        let retainedStatus = try runExclusiveProbe(executable)
        guard retainedStatus != noErr else { throw LocalServiceError.failed("The original F18 registration was lost after a failed update.") }
        service.unregisterAll()
        let releasedStatus = try runExclusiveProbe(executable)
        guard releasedStatus == noErr else { throw LocalServiceError.failed("The temporary F18 registration was not released during cleanup.") }
        let supportedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let reservedBindings = try HotkeyService.systemReservedBindings()
        let systemBinding = reservedBindings.first {
            $0.keyCode <= 127 && $0.modifiers & ~supportedModifiers == 0 &&
            $0.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 &&
            (try? HotkeyService.validateBinding($0)) != nil
        }
        guard let systemBinding else { throw LocalServiceError.unavailable("No enabled system reservation was available for the refusal probe.") }
        var systemRefused = false
        do { try service.update(action: .typed, binding: systemBinding) }
        catch { systemRefused = error.localizedDescription.contains("reserved by an enabled macOS") }
        guard systemRefused else { throw LocalServiceError.failed("An enabled system keyboard reservation was not refused.") }
        let report: [String: Any] = [
            "checks": safetyChecks + [
                "Separate subprocess holds a previously free F19 binding exclusively",
                "Rejected Command+A update preserves active F18 registration, verified from another process",
                "Service exclusive registration refuses the occupied F19 combination",
                "Failed update retains prior F18 binding in memory",
                "Second subprocess cannot exclusively acquire retained F18 binding",
                "Second subprocess can acquire F18 after service unregisters it",
                "CopySymbolicHotKeys enabled system reservation refused before registration"
            ],
            "occupiedBinding": "Control+Option+Command+F19",
            "retainedBinding": "Control+Option+Command+F18",
            "refusal": refusal,
            "retainedRegistrationStatus": retainedStatus,
            "releasedRegistrationStatus": releasedStatus,
            "systemReservedKeyCode": systemBinding.keyCode,
            "systemReservedModifiers": systemBinding.modifiers,
            "controlSpaceReserved": reservedBindings.contains { $0.keyCode == UInt32(kVK_Space) && $0.modifiers == UInt32(controlKey) },
            "optionSpaceReserved": reservedBindings.contains { $0.keyCode == UInt32(kVK_Space) && $0.modifiers == UInt32(optionKey) },
            "nonexclusiveOtherAppConflicts": "Not exhaustively detectable; exclusive ownership may suppress them",
            "preferencesWritten": false,
            "syntheticKeyEvents": 0,
            "bundleUIOpened": false
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    @MainActor
    private static func verifyBindingSafety() throws -> [String] {
        let protectedKeys = [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X,
                             kVK_ANSI_Z, kVK_ANSI_Q, kVK_ANSI_W]
        let isolatedService = HotkeyService(preferences: nil)
        for key in protectedKeys {
            for modifiers in [UInt32(cmdKey), UInt32(cmdKey | shiftKey)] {
                var rejected = false
                do { try isolatedService.update(action: .stop, binding: HotkeyBinding(keyCode: UInt32(key), modifiers: modifiers, label: "Protected shortcut")) }
                catch { rejected = error.localizedDescription.contains("Command-only") }
                guard rejected, isolatedService.bindings.isEmpty else {
                    throw LocalServiceError.failed("An editing or quit shortcut was accepted, or rejection altered registration state.")
                }
            }
        }
        for binding in [
            HotkeyBinding(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey), label: "⌘ F19"),
            HotkeyBinding(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | shiftKey), label: "⇧ ⌘ F19"),
            HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), label: "⌃ Space"),
            HotkeyBinding.defaults[.stop]!
        ] { try HotkeyService.validateBinding(binding) }

        let suiteName = "dev.dotscompanion.in-memory-hotkey-probe.\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: suiteName) else { throw LocalServiceError.failed("Could not create isolated preference view.") }
        preferences.register(defaults: [
            "shortcut.1.keyCode": Int(kVK_Space), "shortcut.1.modifiers": Int(controlKey), "shortcut.1.label": "⌃ Space",
            "shortcut.4.keyCode": Int(kVK_ANSI_A), "shortcut.4.modifiers": Int(cmdKey), "shortcut.4.label": "⌘ A"
        ])
        let startupService = HotkeyService(preferences: preferences)
        let resolved = startupService.startupBindings()
        guard resolved[.stop] == HotkeyBinding.defaults[.stop],
              resolved[.stop]?.keyCode == UInt32(kVK_ANSI_Period),
              resolved[.stop]?.modifiers == UInt32(controlKey | optionKey),
              resolved[.conversation] == HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), label: "⌃ Space"),
              startupService.recoveredStartupActions == [.stop],
              preferences.integer(forKey: "shortcut.4.keyCode") == Int(kVK_ANSI_A),
              preferences.integer(forKey: "shortcut.4.modifiers") == Int(cmdKey) else {
            throw LocalServiceError.failed("Unsafe saved Stop did not resolve to its safe default while preserving valid Conversation and stored values.")
        }
        return [
            "Command and Command+Shift A/C/V/X/Z/Q/W rejected before registration",
            "Command function-key combinations, Control+Space and safe Stop pass structural validation",
            "In-memory saved Command+A Stop resolves to Control+Option+Period",
            "Valid saved Conversation Control+Space remains unchanged",
            "Startup resolution writes no preferences; persistence waits for successful registration"
        ]
    }

    @MainActor
    private static func holdExclusiveBinding() throws {
        // A conflicting existing exclusive registration is refused, never replaced.
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x44545052, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_F19), probeModifiers, identifier,
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else { writeLine("FAIL \(status)"); return }
        defer { UnregisterEventHotKey(reference) }
        writeLine("READY")
        _ = FileHandle.standardInput.readData(ofLength: 1)
    }

    @MainActor
    private static func tryExclusiveF18() -> OSStatus {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_F18), probeModifiers,
                                        EventHotKeyID(signature: 0x44545052, id: 2),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        if let reference { UnregisterEventHotKey(reference) }
        return status
    }

    private static func runExclusiveProbe(_ executable: URL) throws -> OSStatus {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--try-exclusive"]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let status = Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LocalServiceError.failed("The cross-process registration probe failed.")
        }
        return status
    }

    private static func writeLine(_ value: String) {
        FileHandle.standardOutput.write(Data((value + "\n").utf8))
    }
}
