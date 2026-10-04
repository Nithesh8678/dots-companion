# HeyClicky reference and Dots Companion parity inventory

> Historical handoff-phase record. See the [development checkpoint](development-checkpoint.md) for the current direction and source state.

Audit date: 4 October 2026 (Asia/Kolkata). “Documented” below means a vendor claim, not an independently observed reliability result. No live reference audio or private screen content was sent to HeyClicky's service for this audit.

## Reference evidence

- [Homepage](https://www.heyclicky.com/): interaction reference for voice, screen guidance, dictation, and task work.
- [Changelog](https://www.heyclicky.com/changelog): latest entry observed was **1.0.53, 2 October 2026**.
- Installed `/Applications/HeyClicky.app/Contents/Info.plist`: **1.0.53 (64)**, `com.humansongs.clicky`, minimum macOS 14.2. This verifies metadata, not runtime behavior.
- [Public source revision](https://github.com/farzaa/clicky/tree/a80fa80721a8aebe51a170a7780705024ebc6e46): `a80fa80721a8aebe51a170a7780705024ebc6e46`, commit date **27 April 2026**. [README](https://github.com/farzaa/clicky/blob/a80fa80721a8aebe51a170a7780705024ebc6e46/README.md) says later development is private. This is not the source for installed 1.0.53.
- [Pinned license](https://github.com/farzaa/clicky/blob/a80fa80721a8aebe51a170a7780705024ebc6e46/LICENSE): MIT, copyright 2026 Farza. No source or artwork was copied into Dots Companion by this audit. Future reuse requires the notice and a reviewed revision.
- [Pinned overlay source](https://github.com/farzaa/clicky/blob/a80fa80721a8aebe51a170a7780705024ebc6e46/leanring-buddy/OverlayWindow.swift): the older implementation uses click-through screen windows and a cursor character. Its source constants are not measurements of the current app. Dots' notch placement, dot drawing, motion, and controls are independently authored.

The supplied brief reports an earlier blank HeyClicky window capture with little accessibility content. That is prior evidence, not a successful live observation in this audit. Frame-by-frame motion comparison remains **not yet tested**. The existing-dot host UI inspection was separately blocked by tool policy; see [integration capabilities](integration-capabilities.md).

## Reading this inventory

The following records the implemented development build after source review, passing core tests, and successful release packaging. **Built** means the code is present and compiled; **Partial** identifies a smaller implemented scope; **Core only** means isolated logic exists without the corresponding live integration; **Not implemented** means the feature is absent. Specific hardware observations, including the final-build relaunch, are linked in the [smoke-test record](evidence/runtime-smoke.md). Other hardware and account journeys remain pending unless the [runtime ledger](runtime-verification.md) records a pass. No row claims exact reproduction. The user explicitly selected the existing-dot handoff.

Reference keys: **H** = homepage; **C** = changelog with listed version; **B** = user's supplied build brief. Reproduction probes use synthetic content. Source-derived feature labels below are intentionally concise; follow the linked originals for vendor detail.

| Reference feature | Source | Implemented Dots behavior / boundary | Verification probe and known difference | Implementation status |
| --- | --- | --- | --- | --- |
| Voice hotkey | H | Registered summon toggle and manual ChatGPT handoff [K1, K3, K4]. | Compact UI observed; physical registered-shortcut activation and focus/caret preservation remain unverified. No direct dot-call control. | Built; UI observed, shortcut pending |
| Configurable shortcuts | C 1.0.11 | Recorder, persisted combinations, duplicate checks, enabled system-reservation checks, exclusive registration [K2, K4]. | Saved Control + Space persisted; six native cross-process/system checks passed. Other apps’ shared shortcuts may be undetectable and lose priority. Physical trigger pending. | Built; persistence and bounded conflict checks verified |
| Modifier gestures | C 1.0.53 | Pure opt-in gesture recognizer [K15]; native registration uses key combinations. | Seven shortcut logic tests pass; modifier-only gestures are not installed. | Core only; intentionally different |
| Typed input | C 1.0.23 | Focused Home composer supports a bounded local command list [K1, K2]. | Final Home observed. Repeated CUA chord left diagnostic at no registered shortcut received; physical trigger remains unverified. Focus request exists; no natural-language assistant here. | Built; final UI observed |
| Notch peek | C 1.0.52 | Movable 390×128 nonactivating capsule, safe-area placement [K3]. | Compact panel/dot/buttons visually verified. No hover peek or animated notch expansion. Reference motion remains unmeasured. | Partial; compact UI hardware-verified |
| Resizable Home | C 1.0.51 | Resizable SwiftUI workspace in NSWindow with frame autosave [K1, K2]. | Resize/restoration remains untested; original window layout. | Built; hardware pending |
| Standalone Home | C 1.0.51 | Separate Home/Work/Context/Files/Notes/Settings window [K1, K2]. | Dark screenshot inspected; final Home/Work/Settings and native menus observed after relaunch. | Built; final UI observed |
| File drop | C 1.0.23 | Files pane accepts local file URLs and opens files [K1, K2]. | Session-only references; no notch drop, upload, or dot attachment. | Partial; hardware pending |
| File previews | C 1.0.53 | Local filenames/icons/Open plus manual snapshot PNG save [K1, K2]. | No agent-generated file piles or preview feed. | Partial; hardware pending |
| Named agents | C 1.0.49 | Existing-dot ownership label and host handoff [K2]. | No local creation or synchronized identity list. | Intentionally host-owned |
| Task cards | C 1.0.53 | Work shows bounded persisted local action records and observed results; confirmed local-history reset after activity stops [K1, K10]. | Final Work restored Completed Calculator/ChatGPT launch records without replay. Destructive reset source-reviewed only. No remote task feed. | Built; persistence hardware-verified |
| Task follow-ups | C 1.0.53 | Existing-dot follow-ups happen in ChatGPT. | No card composer or remote continuation adapter. | Not implemented locally |
| Retry | C 1.0.43 | Core task identity deduplication exists [K10]. | Unit test verifies same identity; no retry UI or remote retry route. | Core only |
| Routines | C 1.0.53 | Work directs user to ChatGPT [K2]. | No local scheduler or duplicate schedule creation. | Intentionally host-owned |
| Integrations | C 1.0.53 | Work directs user to ChatGPT [K2]. | No local connector authentication or fabricated connected tools. | Intentionally host-owned |
| Multiple accounts | C 1.0.53 | Host chooses the dot’s connected accounts. | No companion account picker; actual account availability remains unverified. | Intentionally host-owned |
| Voice selection | C 1.0.21 | Host voice stays in ChatGPT; local speech helper is source-only [K13]. | No voice picker, live independent audio session, or dot voice mirroring. | Not implemented in UI |
| Speech speed | C 1.0.45 | System speech helper accepts rate in source [K13]. | Helper is not connected to the selected product UI. | Prepared only |
| Interruptions | C 1.0.22 | Stop cancels owned dictation/context/action generations [K1, K5, K8]. | Host call must end in ChatGPT. No independent streaming speech to interrupt in current UI. | Built locally; hardware pending |
| Dictation | H | On-device Apple Speech, partial/final transcript, optional hold [K1, K5]. | Requires available local language; real microphone recognition not yet exercised. | Built; hardware pending |
| Direct insertion | C 1.0.38 | AX target/selection/content checks and postcondition readback [K8]. | Actual AX behavior pending; core refusal tests do not exercise a real editor. | Built; hardware pending |
| Screen explanation | H | One-window local preview, save/discard controls [K1, K6]. | No image analysis or automatic dot transmission. User may attach saved PNG in host. | Partial; hardware pending |
| Drawing | H | Seven annotation primitives; UI exposes fresh window boundary only [K7]. | Click-through, expiry and invalidation are coded. No model-selected control targets. | Partial; hardware pending |
| Spatial input | C 1.0.33 | No region-selection or drawing-input surface. | Whole-window capture only. | Not implemented |
| Walkthroughs | C 1.0.53 | No AI walkthrough coordinator. | Fresh boundary cue is explicitly labelled as a captured-window boundary. | Not implemented |
| Computer use | C 1.0.52 | Bounded app launch and verified text insertion [K8]. | Initial app launched Calculator; separate CUA view confirmed it visible. AX insertion still untested. No universal control. | Partial; Calculator hardware-observed |
| Cursor settings | C 1.0.53 | Movable companion and persisted pinned location [K3]. | Does not replace/move the user’s cursor. | Built; intentionally different |
| Completion notices | C 1.0.52 | Local result text and Work records [K1, K10]. | Initial Calculator result message observed; no spoken announcement or remote signals. | Partial; one local result observed |
| Memory | C 1.0.53 | Editable/removable local Notes; bounded disk persistence [K11]. | Four persistence tests pass. Notes do not synchronize with dot memory. | Built; core-tested; hardware pending |
| Suggestions | C 1.0.52 | No proactive observation or suggestion engine. | No background context collection is installed. | Not implemented |
| Onboarding | C 1.0.53 | Home entry points and individual Settings setup actions [K2, K14]. | Final setup controls/permission statuses observed. No guided tutorial; grants still pending. | Partial; final UI observed |
| Screen permission failure | C 1.0.24 | Explicit error and capture preflight/recheck [K6, K14]. | Separate unbundled CLI refusal probe passed. Bundle Settings shows screen capture unavailable; grant/revoke pending. | Built; CLI refusal verified |
| Network recovery | C 1.0.53 | Selected handoff delegates networking to host. Prepared API adapter reports failures [K12]. | No reconnecting independent voice transport; adapter is unconnected. | Host-owned; adapter prepared |
| Audio route recovery | C 1.0.53 | Dictation cancels with a retry instruction on route change [K5]. | No automatic migration of a live capture stream. | Built refusal; hardware pending |
| Sleep recovery | C 1.0.53 | Owned services stop on sleep; permissions refresh after wake [K1, K5]. | Real sleep/wake not yet exercised. | Built; hardware pending |
| Display recovery | C 1.0.42 | Overlay repositions and annotations clear on screen change [K3, K7]. | Actual external-display transition pending. | Built; hardware pending |
| Duplicate-instance guard | C 1.0.53 | Second instance activates the first and exits [K1]. | Launch twice and observe one owner before claiming runtime success. | Built; hardware pending |
| User login choice | C 1.0.53 | Packaging/app do not install a login item or helper. | Source and script reviewed; no startup persistence feature added. | Intentionally absent |
| Accessibility | B | Native controls/menus, semantic labels, appearance and reduced-motion/transparency handling [K2, K3]. | Final native controls/menus observed; Command-Q exit verified. Full VoiceOver and dynamic preferences pending. | Partial; final UI observed |
| Stop distinctions | B | Hide and Stop local controls; explicit separate host-stop guidance [K1, K3]. | Compact Stop click showed cancelled state and separate host-stop guidance. No active-media cancellation test or remote-stop claim. | Built; Stop UI hardware-verified |

## Motion calibration contract

No timings, springs, easing curves, blur/shadow values, or frame pacing in this report are measured HeyClicky values. The build brief's summon and motion figures remain **proposed design targets**. Source values from the April revision cannot establish current parity.

For each permitted future reference capture, record app version, macOS version, hardware, display identifier, refresh rate, scale, geometry, accessibility settings, capture method, and whether the surface was synthetic. Keep raw user content out of measurement logs. Do not send private screen/audio material to a third party for calibration.

The comparison sheet should record these independently for reference and Dots:

| Transition | Measurement required | Reference result |
| --- | --- | --- |
| Entry | Input timestamp to first visible frame; settled bounds | Not measured |
| Hover/peek | Delay, hit region, expansion curve, pointer exit response | Not measured |
| Expand/reverse | Presentation geometry and velocity through retargeting | Not measured |
| Listening | Actual energy correlation, onset/decay, silence settling | Not measured |
| Speaking | Actual output energy correlation and pause behavior | Not measured |
| Task progress | Source event to displayed state; no simulated progress | Not measured |
| Collapse/dismiss | Duration, opacity, focus/caret restoration | Not measured |
| Error/offline | Stability, actionable copy, retry/cancel response | Not measured |

Use at least 30 warm invocations for an initial local latency distribution; report p50/p95 and the measurement boundary. A UI timing probe measures local feedback, not model response. Use actual hardware capture for frame pacing where available. No 120 Hz claim is justified by a 60 Hz test.

## Completion gate

Promote each relevant row only after linking its build/test evidence. Final reporting must distinguish:

- Implemented in source and build-tested.
- Hardware-verified on the declared Mac and displays.
- Account-verified with the named real backend.
- Experimental with a bounded failure/recovery path.
- Blocked by a precise dependency or tool restriction.
- Intentionally different in identity, artwork, scope, or interaction.

This audit verifies installed metadata, reviewed implementation, release packaging, 35 passing XCTest core tests, and the specific final UI/persistence/quit plus earlier Calculator observations above. Permission-dependent runtime verification remains separate. It does not verify all reference interactions, an existing-dot call, or full HeyClicky parity. A runnable native companion is valuable, but it must not be described as an exact replica or fully synchronized dot client while these gaps remain.

## Reproduce source checks

```sh
curl -fsSL https://www.heyclicky.com/changelog
curl -fsSL 'https://api.github.com/repos/farzaa/clicky/commits?per_page=1'
curl -fsSL https://raw.githubusercontent.com/farzaa/clicky/a80fa80721a8aebe51a170a7780705024ebc6e46/README.md
curl -fsSL https://raw.githubusercontent.com/farzaa/clicky/a80fa80721a8aebe51a170a7780705024ebc6e46/LICENSE
```

For installed version reproduction, use the public metadata probe in [integration-capabilities.md](integration-capabilities.md). Do not derive current product behavior from repository commit age or the presence of a registered URL scheme.

## Implementation evidence map

- **K1** — [AppCoordinator](../Sources/DotsCompanion/AppCoordinator.swift): actual application wiring and bounded local workflows.
- **K2** — [WorkspaceView](../Sources/DotsCompanion/WorkspaceView.swift): user-facing surfaces, availability copy, recorder, and settings.
- **K3** — [OverlayController](../Sources/DotsCompanion/OverlayController.swift): nonactivating panel and dot rendering.
- **K4** — [HotkeyService](../Sources/DotsCompanion/Services/HotkeyService.swift): native registered combinations.
- **K5** — [DictationService](../Sources/DotsCompanion/Services/DictationService.swift): owned microphone and on-device recognition.
- **K6** — [ContextService](../Sources/DotsCompanion/Services/ContextService.swift): scoped single-window snapshot.
- **K7** — [AnnotationService](../Sources/DotsCompanion/AnnotationService.swift): bounded local drawings and invalidation.
- **K8** — [ActionGateway](../Sources/DotsCompanion/Services/ActionGateway.swift): real macOS launch/insertion adapter.
- **K9** — [SessionStateMachine](../Sources/DotsCore/SessionStateMachine.swift): capability and generation rules.
- **K10** — [TaskCoordinator](../Sources/DotsCore/TaskCoordinator.swift): local observed task records.
- **K11** — [MemoryStore](../Sources/DotsCore/MemoryStore.swift): explicit local notes.
- **K12** — [IndependentAssistantAdapter](../Sources/DotsCompanion/Services/IndependentAssistantAdapter.swift): prepared, disabled text/image API adapter; not wired to selected UI.
- **K13** — [SpeechOutputService](../Sources/DotsCompanion/Services/SpeechOutputService.swift): prepared local speech helper; not wired to selected UI.
- **K14** — [PermissionCoordinator](../Sources/DotsCompanion/Services/PermissionCoordinator.swift): explicit setup actions.
- **K15** — [ShortcutGestureMachine](../Sources/DotsCore/ShortcutGestureMachine.swift): tested pure logic; modifier-only native adapter not installed.
- [Final core test output](evidence/core-tests-final.txt): 35 XCTest tests, zero failures, 4 October 2026.
- [Release packaging output](evidence/build-release.txt): compiled and signed development artifact.
- [Hardware observations](evidence/runtime-smoke.md): final Home/Work/Settings, shortcut/task persistence, panel-submission probe, compact visual/Stop UI, Command-Q exit, and earlier Calculator launch.
- [Native service refusal probe](evidence/native-services.txt): seven checks, CLI identity, no permissions requested or private capture.
- [Shortcut conflict probe](evidence/hotkey-conflicts.txt): six native checks; separate exclusive owners and enabled system reservation. No keyboard events, no preference writes, no exhaustive nonexclusive conflict guarantee. [Reproduction and SDK scope](hotkey-conflicts.md).
- [Independent transport fixture](evidence/independent-runtime.txt): offline code verification, no live account or audio.
- [Process samples](evidence/process-samples.json): short Settings-open observation, not a dormant benchmark.

Core tests cover modeled state, focus, geometry, cancellation, and persistence. They do not grant TCC permissions, drive real Accessibility fields, recognize speech, or establish physical display behavior. In particular, `ActionGate` tests exercise the pure contract, while the live `ActionGateway` uses separate AX checks requiring its own integration probes.
