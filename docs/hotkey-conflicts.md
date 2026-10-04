# Shortcut conflict boundaries

> Historical handoff-phase record. See the [development checkpoint](development-checkpoint.md) for the current direction and source state.

`HotkeyService` uses `CopySymbolicHotKeys` to reject enabled macOS symbolic shortcuts before registration, then registers with `kEventHotKeyExclusive`. A failed update preserves the prior working registration and persisted binding. The service never silently substitutes a different key combination.

The current SDK's `RegisterEventHotKey` Result documentation specifies `eventHotKeyExistsErr` when another process already holds that combination exclusively. A real cross-process fixture confirmed that refusal and confirmed that the original shortcut remains registered after a rejected update. The fixture also confirmed rejection of an enabled system shortcut. [Recorded evidence](evidence/hotkey-conflicts.txt).

This is **not exhaustive conflict detection**. The public system-symbolic API excludes application-specific command keys, and the live fixture showed that an existing nonexclusive registration did not prevent a new exclusive registration. Exclusive ownership can suppress notifications to such a registration. The app must tell the user this before recording a replacement binding and must not describe successful registration as proof that no other app uses it.

Suggested settings notice: “Enabled macOS shortcuts and existing exclusive registrations are checked. Other apps may use shortcuts macOS does not expose; this binding can take priority over a nonexclusive shortcut. Choose a combination you do not use elsewhere.”

The recorded system configuration did not list Control+Space or Option+Space as enabled symbolic reservations. That observation is specific to this Mac and this run. Existing exclusive owners can still cause registration failure; other app shortcuts remain the limitation above.

## Reproduce the bounded native test

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path /private/tmp/dots-services-modulecache \
  Sources/DotsCompanion/Services/ServiceError.swift \
  Sources/DotsCompanion/Services/HotkeyService.swift \
  Tests/ServiceProbes/HotkeyConflictProbe.swift \
  -o /private/tmp/dots-hotkey-conflict-probe
/private/tmp/dots-hotkey-conflict-probe
```

This command needs WindowServer access; the execution sandbox returned Carbon `eventInternalErr` before registration. The fixture temporarily registers Control+Option+Command+F18/F19, refuses a conflicting existing exclusive owner, sends no keyboard events, opens no bundle UI, writes no preferences, and releases both registrations before exiting. Run it only when those unusual combinations are not otherwise in use; failure is not permission to override them.
