# Dots integration capability report

> Historical handoff-phase record. See the [development checkpoint](development-checkpoint.md) for the current direction and source state.

Audit date: 4 October 2026 (Asia/Kolkata). This is an evidence report, not a claim that the user's account has passed a live connection test.

## Decision

The user selected a **host-assisted handoff**: Dots Companion opens the installed ChatGPT app and instructs the user to open their dot and select Call. The implemented Home and Settings surfaces say that the call belongs to ChatGPT. Opening an application is not proof of selecting a particular dot, starting a call, or receiving remote work state.

The reviewed official documentation establishes the host's dot conversation and Call controls, supported plugins, and separately granted local-computer access. It does **not establish a public custom-client interface for an existing dot's call audio, transcripts, memory, or lifecycle**, or a supported deep link that selects and calls a dot. This is a bounded conclusion about the sources below, not a statement that no such interface can exist.

An independent OpenAI API assistant is a separate identity with its own conversations and memory. It must remain an explicit user choice, with separate credential and funding setup. It cannot inherit the existing dot simply by using an OpenAI model or ChatGPT authentication.

## Status definitions

- **Verified:** the specified observation actually completed. Documentation verification is labelled as such and never implies account or hardware verification.
- **Experimental:** an implementation path exists but its complete supported journey has not been established.
- **Unsupported:** unavailable in this companion's current integration contract; this does not assert universal absence from OpenAI.
- **Not yet tested:** a real account, call, permission, device, or user-visible result has not been exercised.

## Installed host evidence

Read-only inspection of public bundle `Contents/Info.plist` returned:

| Field | ChatGPT | HeyClicky |
| --- | --- | --- |
| Application | `/Applications/ChatGPT.app` | `/Applications/HeyClicky.app` |
| Bundle identifier | `com.openai.codex` | `com.humansongs.clicky` |
| Marketing version | `26.930.31730` | `1.0.53` |
| Build | `12947` | `64` |
| Declared minimum system | macOS 13.0 | macOS 14.2 |
| Registered URL schemes | `codex`, `http`, `https` | `clicky`, `heyclicky` |

These fields verify installation metadata only. Registered schemes do not prove a particular route. No private account databases, stored credentials, tokens, host binaries, or internal endpoints were inspected.

The implementation team's host UI probe, `cua.getApp("ChatGPT")`, was rejected by the computer-use tool: `Computer Use is not allowed to use app com.openai.codex for safety reasons.` The audit did not bypass that restriction through another automation path. Accordingly, dot selection, call initiation, voice settings, and plugin discovery on this installed account remain unverified. The public metadata probe was separate from UI automation.

## Capability matrix

Statuses describe the **existing-dot route through Dots Companion**, not whether the host advertises the underlying feature.

| Capability | Evidence and boundary | Reproducible acceptance probe | Status |
| --- | --- | --- | --- |
| Find installed host | Public bundle metadata above; launch target is known. | Run metadata probe below and check bundle ID/version. | **Verified**, metadata only |
| Select existing dot | Host profile/conversation is the documented entry point [D1]. No selected-dot identifier contract was established for this companion. | User opens their named dot; record visible identity and app version. Do not infer it from the frontmost app alone. | **Not yet tested** |
| Start dot call | Conversation phone button or profile Call is documented [D1]. | In the selected dot, start Call manually and observe the host's call controls. | **Not yet tested** |
| General voice hotkey | Host Voice settings support a configurable hotkey [V1]. Command reference lists start-voice when available [C1]. Neither proves chosen-dot targeting. | User checks persisted binding; invokes from harmless editor; confirms actual destination. | **Not yet tested** |
| Genuine call state | No external dot event contract established in reviewed sources. | Require a documented event stream and test connected/listening/speaking/ended independently. | **Unsupported** |
| Genuine transcripts | Host supports conversation during a call [D1]; no external transcript subscription established. | Compare a harmless spoken nonce with genuine host transcript events, including finality and cancellation. | **Unsupported** |
| Screen context | General host voice can use deliberate Appshots [V1]. Companion-to-dot snapshot injection is not established. | Use a blank test window with a synthetic label; explicitly share through supported host controls; verify label and scope. | **Not yet tested** |
| Local tools | Dots can use supported plugins; local-computer permission is separate from Codex/Work Sync [D2]. | Enable a bounded test tool, ask the actual dot to call it, and match its nonce/result to a local invocation log. | **Experimental**, unconnected |
| Task updates | Host Activity and delegated tasks are documented [D3, D4]. No existing-dot event subscription verified for this companion. | Start a harmless task from the dot; inspect its actual task ID, result, and update channel. | **Unsupported** for mirrored updates |
| Continue conversation | Same-dot context is host-managed [D1, D4]. Local API sessions are separate. | Give the dot a harmless temporary detail, end Call, reopen the same conversation, and ask a follow-up. | **Not yet tested** |
| Memory ownership | Host memory and dot notes have distinct roles [D4]. Companion cannot read/write or synchronize them through a verified interface. | Ask the actual dot to explain a harmless preference it intentionally retained; inspect supported host controls. | **Unsupported** for synchronization |
| Stop current call | Host call stop control owns the call [D1]. Companion's local Escape cannot prove remote hangup. | End in ChatGPT and observe host call termination; verify no second audio owner exists. | **Not yet tested** |
| Stop remote work | Main task, delegated tasks, and schedules have separate stop controls [D3]. | Use one harmless bounded task and one explicitly approved schedule; stop each in its respective host surface and inspect results. | **Unsupported** from companion |
| Authentication | Existing dot stays authenticated in the host. SIWC is a separate application authorization [S1]. | No token extraction. User signs in using the chosen backend's documented flow and verifies displayed account. | **Not yet tested** for account eligibility |
| Billing/eligibility | Dot eligibility and work limits are plan/rollout dependent [D0]. SIWC and independent audio eligibility are separate [S1, S2]. | User inspects actual account availability/usage; API route tests its own authorized credential. No purchase is required by this audit. | **Not yet tested** |

## Deep-link audit

[The official desktop command reference][C1] retains `codex://` for compatibility and documents local-chat, settings, plugin, skills, schedule, and pet links. `codex://threads/<thread-id>` is described as a **local chat**. It is not evidence that a dot identifier can be placed in that route. The reference also documents Copy chat deep link; a user-copied link would still need manual destination verification before being accepted as a dot handoff.

No dot-selection or dot-call route appeared in the reviewed supported-link list. Do not ship a guessed `codex://dot/...`, `chatgpt://...`, or voice query parameter. Opening `codex://settings` is documented, but an invented settings subpath may fall back to the main settings page. The current default should simply open the known application.

Discovery covered the Dots guides, voice guide, desktop command reference, app-server reference, plugin architecture/testing guides, Sign in with ChatGPT guides, both official documentation indexes, and official-domain searches for Dots API/deep links. It did not involve private application introspection.

## Plugin route: concrete next verification

Plugins can expose a bounded MCP tool [P1]. Official testing supports a reachable HTTPS MCP server or Secure MCP Tunnel, tool inspection, and then testing the installed plugin [P2]. A tunnel needs an appropriate Platform tunnel, runtime credential, workspace association, and separate developer-mode permission [P3]. None was created or installed by this audit.

A proposed first tool is `companion_probe({nonce})`, returning only `{nonce, appVersion, status: "ready"}`. It should not capture a screen, read files, activate an app, or log private content. After transport and authentication checks, the user must ask their **actual dot** to invoke it. Passing the same tool from Codex alone is insufficient.

Acceptance evidence must contain the tool request ID, requested nonce, local receive time, response nonce, visible dot result, and host version. Do not capture the user's real conversation beyond the synthetic probe. A later `show_annotation` tool would need bounded geometry, active user authorization, context freshness, and cancellation validation. Plugin availability does not expose the dot's voice stream or grant new authority.

## Independent runtime and app-server boundary

[Codex app-server][A1] is a documented rich-client interface for local threads, turns, approvals, authentication, and streamed events. Its stdio transport can support a separate task adapter. This is not a documented interface to the user's existing dot. Its WebSocket transport is explicitly experimental in the fetched reference. No app-server credential or account store was inspected.

[Sign in with ChatGPT plan usage][S1] can authorize eligible Responses calls without granting ChatGPT conversation/account context. Its [preview limitations][S2] require specific Responses parameters and exclude audio/video input and transcription through that flow. A separate voice implementation therefore must verify its own API credentials, model access, and billing. Do not advertise that subscription authentication covers API voice.

For an independent adapter, verification must use the exact API family and model chosen in source. A functioning local audio animation or synthetic transport is not a live voice test. No billable voice call was made by this documentation audit.

The current source prepares an independent Responses text/image adapter, Keychain helper, and local speech-output service. They are not instantiated by the selected application coordinator and are not enabled in Settings. There is no independent Realtime voice pipeline in the product. The delivered host handoff does not read a provider key or send its snapshots through that prepared adapter. See the [architecture handoff](architecture-handoff.md).

## Reproducible read-only probes

Public installation metadata, without account data:

```sh
python3 - <<'PY'
import json, pathlib, plistlib
for name in ("ChatGPT", "HeyClicky"):
    path = pathlib.Path("/Applications") / (name + ".app") / "Contents/Info.plist"
    data = plistlib.loads(path.read_bytes())
    keys = ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
            "CFBundleURLTypes", "LSMinimumSystemVersion")
    print(json.dumps({"path": str(path), **{k: data.get(k) for k in keys}}, indent=2))
PY
```

Refresh the official route evidence:

```sh
curl -fsSL https://learn.chatgpt.com/docs/dots/channels.md
curl -fsSL https://learn.chatgpt.com/docs/dots/computers-and-apps.md
curl -fsSL https://learn.chatgpt.com/docs/reference/commands.md
```

Public HTTP fetches succeeded after the execution environment allowed outbound networking. The browser retrieval tool could fetch HTML but rejected Markdown content type; ordinary HTTPS retrieval of the public `.md` versions succeeded. That retrieval limitation is unrelated to product integration support.

## Source ledger

All sources were fetched on 4 October 2026. Public documentation is mutable; recheck before changing capability flags.

- [D0 — Dots overview and access][D0]
- [D1 — Messaging and calls][D1]
- [D2 — Computers and apps][D2]
- [D3 — Controls][D3]
- [D4 — Tasks and memory][D4]
- [V1 — ChatGPT Voice][V1]
- [C1 — Desktop commands and supported deep links][C1]
- [P1 — Plugin architecture][P1]
- [P2 — Connect and test a plugin][P2]
- [P3 — Secure MCP Tunnel][P3]
- [A1 — Codex app-server][A1]
- [S1 — Sign in with ChatGPT plan usage][S1]
- [S2 — Preview limitations][S2]
- [ChatGPT documentation index](https://learn.chatgpt.com/llms.txt)
- [Developer documentation index](https://developers.openai.com/llms.txt)

[D0]: https://learn.chatgpt.com/docs/dots
[D1]: https://learn.chatgpt.com/docs/dots/channels
[D2]: https://learn.chatgpt.com/docs/dots/computers-and-apps
[D3]: https://learn.chatgpt.com/docs/dots/controls
[D4]: https://learn.chatgpt.com/docs/dots/tasks-and-memory
[V1]: https://learn.chatgpt.com/docs/features/voice
[C1]: https://learn.chatgpt.com/docs/reference/commands
[P1]: https://developers.openai.com/plugins/concepts/plugins
[P2]: https://developers.openai.com/plugins/deploy/connect-chatgpt
[P3]: https://developers.openai.com/api/docs/guides/secure-mcp-tunnels
[A1]: https://learn.chatgpt.com/docs/app-server
[S1]: https://developers.openai.com/siwc/token-sharing-open-source
[S2]: https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
