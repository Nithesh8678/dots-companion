# Runtime verification ledger

> Historical handoff-phase record. See the [development checkpoint](development-checkpoint.md) for the current direction and source state.

Prepared 4 October 2026 (Asia/Kolkata). This file is a test ledger, not a blanket completion certificate. Replace “not yet run” only with an observed result and a reproducible command or journey.

**Current boundary:** the final release bundle and zip passed packaging checks. The final app was relaunched, Home/Work/Settings and native menus inspected, saved shortcut/task persistence confirmed, a panel-submission probe run, and Command-Q process exit verified. Calculator launch was observed earlier in the session. The last diagnostics build was also relaunched, its compact panel/Stop UI verified, and Home left open. Microphone, capture, insertion, physical shortcut activation, dot-call, and reference-motion gates remain separate and unverified. [Smoke-test record](evidence/runtime-smoke.md).

## Environment

| Item | Observed value |
| --- | --- |
| macOS | 26.6.2 (25G83), from `sw_vers` |
| Toolchain | Apple Swift 6.4, `swiftlang-6.4.0.34.1`; package uses Swift 5 language mode |
| Compiler target | `arm64-apple-macosx26.0` |
| Package minimum | macOS 14.0; not equivalent to runtime testing on macOS 14 |
| Selected backend | Existing-dot host handoff |
| Build identity | `dev.nithesh.DotsCompanion`, development version 0.1.0 (1) |
| Signing | Ad-hoc signature verified; hardened runtime; audio-input entitlement only; no Developer ID or notarization |
| Reference version | HeyClicky installed 1.0.53 (64); public source is an older April revision |

## Build and artifact checks

| Check | Reproduction | Result/evidence |
| --- | --- | --- |
| Final unit tests + debug app build | `swift test --build-system native --disable-sandbox` | **Passed:** 35 XCTest tests, 0 failures. [Final output](evidence/core-tests-final.txt). Earlier run also passed [35 tests](evidence/core-tests.txt) |
| Release build | `./scripts/build-app.sh` | **Passed:** native engine, release, arm64. [Final build output](evidence/build-release.txt). Initial SwiftBuild `dsymutil: Operation not permitted` failure was resolved by selecting the native engine |
| Bundle structure | Inspect `dist/Dots Companion.app/Contents` | **Passed:** executable, plist, resources, generated ICNS, and code signature present |
| Plist validity | `plutil -lint Resources/Info.plist Resources/DotsCompanion.entitlements` | Passed: both files reported OK on 4 October 2026 |
| Script syntax | `bash -n scripts/build-app.sh` | Passed: exit 0 on 4 October 2026 |
| Signature | `codesign --verify --strict --verbose=2 "dist/Dots Companion.app"` | **Passed:** valid on disk and designated requirement satisfied; ad-hoc development signature |
| Entitlements | `codesign -d --entitlements :- "dist/Dots Companion.app"` | **Passed:** only `com.apple.security.device.audio-input` enabled |
| Zip integrity | `unzip -t "dist/Dots Companion.zip"` | **Passed**, implementation team observation |
| Original icon | Inspect `Resources/AppIcon.icns` and bundled copy | **Passed:** valid code-drawn ICNS; no reference artwork copied |
| Running app | Launch final `dist/Dots Companion.app`, then inspect controls | **Passed:** latest diagnostics build relaunched; final Home/Work/Settings and native menus observed. Compact dot/buttons legible; app left in Home |
| Clean quit | CUA Command-Q, then `pgrep -x DotsCompanion` | **Passed for idle final app:** PID 71803 existed before; after Command-Q, `pgrep` returned exit 1 with no process. No active audio/capture teardown test was performed |

## Live journeys

Use a synthetic text document and harmless apps. Do not send private screen/audio to an external provider to fill a test row.

The core suite is model-level evidence. It does not exercise TCC, a physical microphone, actual Accessibility insertion, provider accounts, or display behavior. The trailing Swift Testing `0 tests` line in the log is a separate runner; the XCTest suite above it executed 35 tests.

Test reproduction used:

```sh
mkdir -p /private/tmp/dots-companion-module-cache /private/tmp/dots-companion-clang-cache
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/dots-companion-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/dots-companion-clang-cache \
swift test --build-system native --disable-sandbox
```

SwiftPM reported non-fatal inaccessible user-cache and read-only manifest-cache warnings. Final native-engine logs also warn that the native engine is deprecated. The earlier `NSEvent` concurrency warning was fixed and is absent from the refreshed final build/test logs. The package currently compiles in Swift 5 language mode. Remaining cache/deprecation warnings are preserved, and the build/test processes exited successfully. `--disable-sandbox` disables SwiftPM's build-script sandbox for this local package; it does not bypass macOS privacy permissions or the separate host UI tool restriction.

| Core suite | Tests | Verified contract |
| --- | --- | --- |
| ActionGateTests | 8 | Changed/secure target refusal, permissions, generation, deduplication, bounded capacity |
| GeometryTests | 4 | Context freshness, display/context identity, invalid geometry, Retina/negative-origin transform |
| MemoryStoreTests | 4 | Round trip, edits/removal, bounds, invalid archive preservation |
| SessionStateTests | 6 | Host capability limits, cancellation, stale session/turn rejection, hide versus stop |
| ShortcutGestureTests | 7 | Repeat suppression, opt-in gestures, ordinary shortcut contamination, hold/cancel boundaries |
| TaskCoordinatorTests | 6 | Verified completion, stable identity, child stop, capacity, interrupted restoration |

| Journey | Pass condition | Current result |
| --- | --- | --- |
| Passive summon | Intended panel appears; frontmost app, selection, and caret preserved | **Compact visual pass:** dot, saved shortcut label and Open ChatGPT/Home/Stop/Hide visible. Submission probe: 50 calls, PID unchanged 50/50; baseline unlogged. Physical hotkey and external-focus/caret preservation remain unverified |
| Shortcut persistence | Changed binding survives restart and triggers exactly once | **Persistence passed:** saved Control + Space remained after final relaunch. Physical trigger pending; exclusive/system conflict probe passed separately. Settings controls the current binding |
| Conflict handling | Enabled system reservation or existing exclusive owner is refused; previous registration survives a rejected update | **Native fixture passed:** six checks, separate subprocesses, no preference writes or synthesized events. [Evidence](evidence/hotkey-conflicts.txt). Other apps’ shared shortcuts are not exhaustively detectable and may lose priority; physical trigger remains pending |
| Typed surface | Explicit focus, useful typed action, predictable return | Home controls observed. Repeated CUA Control + Option + Space left diagnostic at “No registered shortcut received in this run”; automation did not reach the handler. Physical activation remains **unverified**; source focus request is implemented |
| Host launch | Actual intended application process observed | Not yet tested |
| Existing dot identity | User confirms named dot in host | Blocked for automated inspection by host tool policy; no manual result recorded |
| Existing dot call | Host visibly shows the selected dot's real call | Not yet tested; launch alone is insufficient |
| Dot plugin probe | Actual dot returns local tool nonce matching invocation log | Not connected / not yet tested |
| Local dictation | Real harmless speech yields reviewable transcript | Not yet tested |
| Direct insertion | Expected text visible in original supported field | Not yet tested |
| Focus changed | Insert refused after changing app/field/selection | Not yet tested |
| Secure field | Password-field insertion refused | Not yet tested |
| Context snapshot | Correct foreground test window, metadata, geometry; no unrelated window | Not yet tested |
| Annotation | Correct synthetic target, click-through behavior, expiry/removal | Not yet tested |
| App action | Harmless app launched; result reports observed presence | **Hardware-observed earlier in session:** Home's Open Calculator succeeded; independent CUA view confirmed Calculator visible. Final Work preserved that Completed result without replay |
| Cancellation | No new local action or stale callback after stop | **Stop UI pass:** clicking compact Stop displayed cancelled dot state, “Local activity stopped,” and separate host-stop guidance. No active microphone/capture/action race was exercised |
| Permission denial | Feature reports useful fallback, no forbidden capture | Settings showed mic/speech Not requested, screen/AX Not allowed. [Separate CLI native probe](evidence/native-services.txt) passed safe refusal without requesting permissions; bundle grant/deny journey pending |
| Permission revocation | Owned capture/control ceases | Not yet tested |
| Local memory | Explicit note can be inspected, edited, removed; ownership label clear | Not yet tested |
| Task persistence | Restart restores genuine local records without replaying action | **Passed:** final Work displayed earlier Completed Calculator and ChatGPT launch records without replay. Host record proves local launch bookkeeping, not dot identity/call |
| Local-history reset | Explicit confirmation; refuses active/nonterminal work; resets only local task/session history | **Source-reviewed and compiled:** confirmed Work control and guarded reset exist. Destructive reset was not executed on the user’s history; notes/files/host work are separate |
| Reduce Motion/Transparency | Preference changes honored during use | Dark appearance visually inspected. Dynamic Reduce Motion/Transparency not yet tested |
| VoiceOver/keyboard | Controls named, focus order usable, no keyboard trap | Home/Work/Settings and native menus observed; Command-Q passed. Full VoiceOver/keyboard navigation not yet tested |
| Multi-monitor | Correct display transforms and one companion | Not yet tested |
| Display removal | Overlay relocates safely; no off-screen controls | Not yet tested |
| Fullscreen/Spaces/Stage Manager | Usable placement without focus theft or duplicate overlay | Not yet tested |
| Sleep/wake | Capture stops; stale operations stay cancelled; later invocation works | Not yet tested |
| Audio-route changes | Clear recovery/refusal; no stuck microphone | Not yet tested |
| Offline mode | Truthful local/host distinction and recovery | Not yet tested |
| Rapid retrigger | No duplicate session, insertion, or stale-animation snap | Not yet tested |

## Performance

These are required measurements, not achieved values. Report actual instrument, sample count, hardware, and boundaries. Do not equate function duration with the first displayed frame or a model response.

| Metric | Proposed target from brief | Measured result |
| --- | --- | --- |
| Warm summon to first visible frame | p95 at or below 100 ms | Not measured; the submission probe below does not test this target |
| Panel `orderFront` submission | Diagnostic only; no response-time target | 50 submissions, p95 **0.02 ms**; PID unchanged 50/50. No first-frame, caret, or known-external-focus measurement |
| Owned playback cancellation | Within 100 ms | Not applicable to host call; local measurement pending |
| New local actions after cancellation | Zero | Pure gate/session/task cancellation tests passed; actual dispatch race probe pending |
| Dormant CPU | Around or below 1% | Not measured. Separate 18-second Settings-open sample reported 0.0% CPU; not a dormant/energy benchmark |
| Idle microphone/screen stream | None | Runtime inspection pending |
| Memory over repeated sessions | No unbounded growth | Not measured across sessions. Settings-open sample RSS 106.5–110.5 MiB; [raw samples](evidence/process-samples.json) |
| Frame pacing at 60 Hz | Record missed frames | Not measured |
| Frame pacing at 120 Hz | Requires suitable display | Not tested |
| First spoken response | Model/network-specific target only | Existing-dot event stream unavailable to companion |

The separate [independent transport fixture](evidence/independent-runtime.txt) passed eight local checks with four intercepted requests, zero network requests, and no real audio. Its approximately 0.20 ms synthetic HTTP cancellation measurement is **not** a playback-stop measurement, provider latency, or live voice result. The [native service probe](evidence/native-services.txt) passed seven bounded validation/refusal checks under an unbundled CLI identity; its permission values do not describe the app bundle. These two probes total 15 baseline checks. The separate [cross-process hotkey probe](evidence/hotkey-conflicts.txt) passed six additional checks using temporary exclusive registrations and a real enabled system reservation, without keyboard events or preference writes. It does not prove physical delivery or exhaustive detection of nonexclusive owners.

## Distribution boundary

Successful local signing does not establish Developer ID signing, notarization, Gatekeeper acceptance on another Mac, public distribution, or Intel support. No signing credential, paid service, persistent helper, analytics setup, or publication was authorized by the packaging task.

## Completion classification

Use these independent labels in the final handoff: **implemented**, **build-tested**, **hardware-verified**, **account-verified**, **experimental**, **blocked**, and **intentionally different**. Link each promoted claim to evidence in this ledger. The integration and parity reports remain authoritative about external boundaries.
