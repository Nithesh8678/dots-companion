# Direct hotkey-to-dot call recheck

> Historical handoff-phase record. See the [development checkpoint](development-checkpoint.md) for the current direction and source state.

Rechecked official documentation on 4 October 2026 after the user clarified that opening ChatGPT is insufficient: the desired result is a hotkey that starts speaking with the existing dot. The packaged host handoff does **not** satisfy that requirement. This report does not promote the current build to a completed voice product.

## What the documentation establishes

| Surface | Documented behavior | Does this establish the requested existing-dot call? |
| --- | --- | --- |
| Dot conversation/profile | Start a call using the conversation phone control or profile Call action. [Dots messaging](https://learn.chatgpt.com/docs/dots/channels) | Yes for manual host use; no documented external invocation contract in this source |
| Host voice settings | Configure a voice hotkey in Settings > Voice. Existing supported Codex tasks can use their conversation during voice. [Voice](https://learn.chatgpt.com/docs/features/voice) | Dot targeting and background invocation behavior remain unverified |
| Host keyboard command | Control + Shift + V is the macOS default for starting voice when available; bindings can be customized. [Commands](https://learn.chatgpt.com/docs/reference/commands) | An app command is documented, but no promise that it calls the selected dot from another app |
| Supported deep links | The published list covers local chats, settings, connections, skills, schedules, plugins, and pets. [Supported links](https://learn.chatgpt.com/docs/reference/commands#deep-links) | No dot-selection/call route is established by the reviewed list; do not invent one |
| Floating host pet/Mini | Option + Space brings up Quick Chat controls; their voice control starts voice. These controls start a chat outside a project. [Pets](https://learn.chatgpt.com/docs/pets) | A built-in floating voice surface, but not documented as the existing dot conversation |
| Available task tools | The exposed tool inventory contains `end_realtime_voice_call`, with no corresponding start-call tool. | This session cannot start a dot call through an available purpose-built tool |
| GPT-Live API | Supports an application's own live voice session and backend; requires a project API key and separately billed session/backend usage. [GPT-Live](https://developers.openai.com/api/docs/guides/live) | A route to a separate assistant; no inherited dot identity, account tools, or memory established |

This is a bounded audit of current public documentation and exposed tools, not proof that no future or account-specific capability can exist. The host computer-use tool explicitly rejected access to `com.openai.codex`; no alternate UI automation or private endpoint inspection bypassed it.

## Smallest useful existing-dot verification

This needs the user to operate the host because its UI is unavailable to this task's automation:

1. Open the intended dot's actual conversation and confirm its identity.
2. Inspect the host's Voice hotkey setting and its current binding; do not assume the default app command is the global binding.
3. Invoke that host-owned hotkey while the dot is active, and observe whether the same dot begins a real call. Repeat from a harmless foreground app if background invocation is required.
4. Record the host version, binding, actual destination, call controls, and whether a harmless spoken nonce receives a spoken response. Stop through the host.

The companion should not register the same combination exclusively while testing a host-owned shortcut. Its native service can detect enabled system reservations and existing exclusive owners, but not all nonexclusive registrations; it may take priority over a shared shortcut. The documented host pet default Option + Space also overlaps the companion's source default. Preserve the user's chosen binding and verify ownership explicitly.

A successful manual test could establish a host-native shortcut workflow for this account. It would still not expose the host's listening, speaking, transcript, memory, or task events to the custom companion. A local animation or successful app activation is not evidence of a call.

## Product choices after verification

- Preserve the existing dot by using an actually verified host voice shortcut or supported future call interface. The current app-launch handoff is only an interim capability.
- Use the host's floating pet/Mini voice surface when a general host voice conversation is acceptable; first verify whether its destination meets the user's needs.
- Build a separate GPT-Live/Realtime voice assistant when the user explicitly accepts a different identity, separate memory/tool wiring, and API credentials/billing. This does not silently fulfill the existing-dot requirement.

Changing UI copy cannot fill the missing call-control integration. Neither can a plugin tool, which lets a dot invoke a tool after a session exists without establishing an external start-call API.
