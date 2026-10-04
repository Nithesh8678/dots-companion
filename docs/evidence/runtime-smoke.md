# Native smoke-test observations

> Historical handoff-phase record. See the [development checkpoint](../development-checkpoint.md) for the current direction and source state.

Recorded 4 October 2026 from the implementation team's live CUA inspection. The observations below distinguish the early running app from the subsequent **final packaged app** relaunch.

## Earlier session observations

- Launched `dist/Dots Companion.app`.
- Home returned a full accessibility tree. A dark-appearance screenshot was visually inspected; its content and controls were legible.
- The Home action **Open Calculator** produced the companion's process-identity verification message. A separate CUA inspection then found Calculator visibly open. Existing Calculator content was not copied or retained in this report.
- Settings exposed the Home, Work, Context, Files, Notes, and Settings navigation and expected setup controls.
- The app's Settings reported **Microphone: Not requested**, **Speech Recognition: Not requested**, **Screen Recording: Not allowed**, and **Accessibility: Not allowed**. These are bundle-scoped UI observations at that moment; they are not the CLI probe's permission identity.
- The user was actively adjusting settings. The conversation shortcut was observed as **Control + Space** during the session. This is a historical observation, not a fixed binding to reapply. Settings remains the source of truth, and the user's choices were preserved.
- The host probe for `com.openai.codex` remained blocked by the computer-use tool's policy. No alternate automation bypassed it, and no existing-dot call was observed.

## Final packaged app verification

The earlier test process was stopped with SIGTERM, matching only the generated Dots Companion app. That step was **not** counted as a clean-quit test. CUA then launched the final `dist/Dots Companion.app`.

- Final Home exposed the new native **Dots Companion** and **Edit** menus.
- The user's saved **Control + Space** conversation binding remained after relaunch. It was observed, not reset or imposed by the test.
- Final Work displayed the earlier real **Completed** Calculator and ChatGPT application-launch records. They persisted without replaying those actions. A ChatGPT launch record is not a dot identity, call, or remote task verification.
- Final Settings still reported microphone/speech **Not requested** and Screen Recording/Accessibility **Not allowed**.
- The Settings panel-submission diagnostic ran **50 submissions**. It reported **p95 0.02 ms** and frontmost PID unchanged **50/50**. It measures synchronous `orderFront` submission, not first rendered pixels, caret/selection, or model latency. The baseline PID was not logged, so this is not proof that an external app retained focus.
- After the final diagnostic-label build was packaged and relaunched, CUA repeated **Control + Option + Space**. Settings still reported **“No registered shortcut received in this run.”** The automation did not reach the registered handler. Physical shortcut activation remains unverified; this does not establish a physical-key failure. The source implements a focused-composer request.
- A separate, actual **Command-Q** test used only CUA's keyboard action. The final app's PID was **71803** before quitting. Afterwards, `pgrep -x DotsCompanion` returned **exit 1 with empty output**. This verifies idle app process exit; there was no active microphone/screenshot stream to test during quit.

- The latest compact panel was visually inspected after closing Home: original dot, current **Control + Space** label, and **Open ChatGPT**, **Home**, **Stop**, and **Hide** controls were legible. This is visual/UI evidence, not a hotkey delivery or frame-timing result.
- Clicking compact **Stop** produced the accessible dot state **cancelled**, the **Local activity stopped** message, and explicit guidance to stop ChatGPT calls/tasks separately. No active microphone or screen capture was running, so active-media cancellation is not established.
- The latest app was returned to **Home** and left open for handoff.

No real microphone dictation, screen snapshot, AX insertion, live provider API call, remote task cancellation, or full reference motion comparison passed in these observations. Permission-dependent live checks await the user's setup decision. The final app's launch, persistence, menu inspection, diagnostic execution, compact visual/Stop UI, and idle quit are verified within the specific scopes above. The idle Command-Q test preceded the last diagnostic-label-only rebuild; the latest app was successfully relaunched and left open.

## Static-process sample

[process-samples.json](process-samples.json) contains ten samples at two-second intervals for PID 69566, with Settings open. The user could interact. Reported CPU was 0.0% at each sample; RSS ranged from 106.5 to 110.5 MiB. This short snapshot is neither a dormant-state benchmark nor an energy, idle-capture, frame-pacing, or repeated-session memory test.

## Final artifact packaging evidence

The final release build log is [build-release.txt](build-release.txt): native engine, arm64, release compilation passed, as did plist lint and strict signature verification. The implementation team separately verified the archive with `unzip -t`, inspected the entitlement set (audio-input only), and confirmed the generated original icon is valid ICNS. Final CUA relaunch used this generated app.
