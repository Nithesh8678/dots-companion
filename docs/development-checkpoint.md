# Development checkpoint — 4 October 2026

Feature work was stopped at the owner's request. This file records the resume point; the README describes the project itself.

## Decision to preserve

The original implementation used an existing-dot handoff to ChatGPT. It could open the host, but could not start or observe the selected dot's call. The owner manually tested ChatGPT's voice shortcut and reported that it started a different voice chat.

The selected direction is now a **separate local assistant**: Apple on-device speech recognition → Ollama `qwen3:8b` → Apple system speech. The architecture was explained as having no API/per-minute charges, using local CPU/GPU, memory, and battery. No cloud provider has been enabled, no paid request made, and no local inference server was started for this transition.

## Source at the pause

- The earlier handoff app was built, packaged, and inspected before this transition. Its development bundle is local-only and excluded from Git.
- `WorkspaceView.swift`, `OverlayController.swift`, and bundle metadata contain the beginning of the local-voice transition.
- `WorkspaceView` references voice properties and methods not yet added to `AppCoordinator`. **This source snapshot is not a buildable application.** Preserve it as the requested work checkpoint; do not treat historical build logs as verification of current HEAD.
- `VoiceTurnLifecycle.swift` and its eight new tests contain the pure state/lifecycle foundation.
- `VoiceConversationController.swift` and `LocalAssistantAdapter.swift` were discussed but were **not created** before work stopped.
- The Responses API adapter and system speech service are separate prepared modules. The API adapter remains disabled and is not connected to the UI.
- Hotkey safety now rejects Command/Command+Shift editing combinations, preserves valid saved bindings, and replaces an unsafe saved binding with its action's default only after successful registration. Stop defaults to Control+Option+Period.
- History clearing now saves the empty store before discarding visible records; a failed save preserves the old history.

## Resume sequence

1. Implement the local Ollama adapter using an owned loopback server, cloud disabled, no automatic model downloads, no credentials, bounded conversation history, actual streamed text, and cancellation that retires stale callbacks.
2. Implement the voice controller using the existing dictation and speech services. Request microphone and speech permission only on explicit start. Use observed audio events for state, stop capture during playback, finish a turn after a pause, and let the shortcut interrupt an answer.
3. Connect the controller to `AppCoordinator` and the new Home controls. Keep standalone dictation separate. Make panel dismissal and Stop end local voice. Retain verified action results and guard against stale callbacks.
4. Rebuild before packaging. Test typed inference first, then actual microphone → transcript → local reply → audible playback → follow-up, with the owner granting macOS permissions.
5. Verify interruption, no-speech timeout, permission denial/revocation, device changes, sleep, restart, and normal quit. Do not infer whole-journey success from passing isolated tests.
6. Reconcile historical documents and package only after current source passes its checks.

## Checkpoint verification

The current core library passed **43 XCTest tests** in an isolated Swift package, including all eight new voice-lifecycle tests. The app build was also checked and fails at the intentionally interrupted voice UI wiring described above. No feature repairs were made after the stop request. See [core test output](evidence/checkpoint-core-tests.txt) and [application build output](evidence/checkpoint-build.txt).

## Historical evidence

The earlier handoff implementation had 35 passing core tests, 7 native-service probe checks, and 8 optional-runtime offline checks. The final hotkey probe passed 12 checks; its result is in `Tests/ServiceProbes/HotkeySafetyResult.json`.

Files under `docs/evidence/` and the earlier architecture, integration, and verification documents describe the earlier handoff phase unless labelled otherwise. They remain useful evidence, but their selected-backend and build statements are superseded by this checkpoint.

No live microphone conversation, screen capture, or Accessibility insertion was accepted as verified during this session. A local Calculator launch was observed. The accidental Command+A registration belonged to the previous development process, which was terminated before this checkpoint; its source fix still needs packaged-app verification.

## Development commands

After completing the interrupted wiring, the repository's ordinary checks are:

```sh
swift test --build-system native --disable-sandbox
./scripts/build-app.sh
```

The package declares macOS 14+ and Swift 6+. Local development used Apple silicon, macOS 26.6.2, and Swift 6.4. The native SwiftPM engine was used because the default engine encountered a restricted-environment `dsymutil` error. `--disable-sandbox` here is a SwiftPM build option, not a request to alter macOS security settings.

The build script produces an ad-hoc signed app; it does not provide Developer ID signing, notarization, installation, a login item, or production distribution.
