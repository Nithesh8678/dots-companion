# Implemented architecture and ownership

> Historical handoff-phase record. See the [development checkpoint](development-checkpoint.md) for the current direction and source state.

This describes the source reviewed on 4 October 2026. The arm64 release package validates and 35 core XCTest tests pass. The final build was relaunched, its native and compact UI inspected, settings/task persistence checked, compact Stop state observed, and idle Command-Q process exit verified. The latest diagnostics build was relaunched and left in Home. Physical shortcut delivery remains unverified. Calculator launch was observed earlier in the session. Hardware and account behavior are independently tracked in [runtime verification](runtime-verification.md).

## Active product path

`Program` starts an accessory AppKit application. `AppCoordinator` owns one SwiftUI workspace and one nonactivating companion panel. `WorkspaceView` exposes Home, Work, Context, Files, Notes, and Settings. UserDefaults persists preferences/shortcuts; bounded JSON archives preserve explicit local notes and task records under the user's `Application Support/DotsCompanion` directory. These stores are app-owned and do not synchronize with ChatGPT.

The selected assistant route is **existing-dot host handoff**. `openHost()` stops owned local services, launches `com.openai.codex`, and reports only application-opening state. The user selects the actual dot and starts Call in ChatGPT. A conservative microphone ownership flag prevents local dictation until the user declares the host call ended. This flag is a local guard, not a measured call state.

The local command composer accepts an explicit allowlist: opening Calculator, TextEdit, or ChatGPT, and stopping local work. Other text is left for user-directed copying to the dot. There is no general natural-language action executor or shell tool.

## Service wiring

| Module | Active use | Boundary |
| --- | --- | --- |
| HotkeyService | Enabled symbolic-system reservation checks, exclusive Carbon registration, persisted bindings, repeat suppression | Rejected updates preserve the prior binding; other apps’ nonexclusive shortcuts cannot be exhaustively detected. Ordinary combinations only; no modifier-only event adapter |
| OverlayController / DotRenderer | Safe-area placement, movable panel, fade retargeting, genuine local microphone meter | No host listening/speaking/task telemetry; original artwork/motion |
| DictationService | AVAudioEngine plus on-device-only SFSpeechRecognizer | Refuses unsupported model/language; no API audio or dot transcript |
| ContextService | One explicit foreground-window screenshot with provenance and post-capture checks | Local review/save/discard only; no continuous observation or automated upload |
| AnnotationService | Seven bounded click-through primitives with invalidation/expiry | UI exposes only a fresh, unchanged captured-window boundary; no AI target inference |
| ActionGateway | Public application launch and AX selected-text insertion | Focus/content/selection/cancellation checks; no arbitrary automation or guessed clicks |
| PermissionCoordinator | Read status and explicit request/setup actions | Does not grant/revoke system permissions itself |
| TaskCoordinator | Persist observed local action results and interrupted-state recovery | Does not mirror the dot's Activity, child tasks, or scheduler |
| MemoryStore | Explicit local Notes creation/edit/removal | No passive memory collection or host synchronization |

## Prepared modules, not active product capabilities

- `IndependentAssistantAdapter` / `ResponsesTextTransport`: disabled, separate text/image API runtime with bounded conversation history, SSE parsing, HTTP cancellation, and no tools. It is not wired to `AppCoordinator` or the Settings UI. No live API success is claimed.
- `SpeechOutputService`: local AVSpeechSynthesizer with utterance-identity checks, source-level rate/voice configuration, and explicit stop. It is not a second active voice owner in the chosen handoff product.
- `KeychainService`: credential storage for the independent adapter; the active host route does not read ChatGPT credentials.
- `Diagnostics`: bounded numeric in-memory measurement utility. The current Settings benchmark separately measures panel submission calls; it is not a first-visible-frame, audio latency, or model-response measurement.
- `ShortcutGestureMachine`: tested modifier gesture model. Passing those tests does not mean the native app registered Control-only gestures.
- `ActionGate` and `DotsCore.ContextSnapshot`: pure action/context contracts tested in isolation. The actual macOS `ActionGateway` and `ContextService` have platform-specific checks; their live journeys must still be exercised. Core test coverage cannot be presented as real Accessibility insertion coverage.

## Cancellation and persistence

Local work uses generation counters and owned Swift Tasks. Stop invalidates callbacks, cancels dictation/capture, rejects stale action dispatch, and clears annotations. An in-flight application launch whose observation stops becomes **unverified**, because macOS may already have dispatched it. Already opened applications remain open; completed external effects are not undone. Hide is visual. Host calls, delegated tasks, and schedules must be stopped separately in ChatGPT.

The final source explicitly separates dictation startup, listening, and finalization, rejects a released hold before capture begins, binds callbacks to a local generation, rechecks permission changes, and restores the previous app when the workspace closes. The final app launches and quits successfully. The microphone-, capture-, and insertion-dependent lifecycle paths remain unverified because the necessary permissions were not granted during this run.

On restart, in-flight persisted local tasks become unverified rather than replaying. The task store holds at most 128 records and refuses new identities when full rather than silently forgetting retry identities. Work offers a confirmed **Clear local history…** reset, allowed only when owned activity has stopped and all records are terminal. It starts a fresh local session and persists an empty task store. Notes, files, and host work are separate. The reset is source-reviewed and compiled; it was not executed against the user's history.

File references are deliberately session-only. Snapshots are in memory until discarded, stopped, or explicitly saved. Notes are explicit local data; transient captures are not silently promoted into notes.

The [cross-process shortcut fixture](evidence/hotkey-conflicts.txt) verifies refusal of an existing exclusive owner, preservation of the old registration, and enabled system-reservation rejection. macOS does not expose every application-specific or shared shortcut. An exclusive binding can suppress a nonexclusive owner; the service must not promise exhaustive conflict detection. [Reproduction and SDK boundary](hotkey-conflicts.md).

## Remaining integration work

Existing-dot calls, memory, task events, direct call shortcuts, and tool discovery still require a supported interface and account-specific proof. No guessed route or token extraction is part of this build. A future plugin should begin with a nonce-only local tool called by the actual dot, as specified in the [integration capability report](integration-capabilities.md).

Full reference parity still needs hover/expansion behavior, drawing input, model-guided walkthroughs, richer task interactions, and frame/hardware measurements. Routines and account connections intentionally remain in the host for the selected identity.
