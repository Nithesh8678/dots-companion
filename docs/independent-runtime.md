# Optional independent runtime

> Historical handoff-phase record. See the [development checkpoint](development-checkpoint.md) for the current direction and source state.

The chosen product route is the existing-dot handoff in ChatGPT. `IndependentAssistantAdapter` is compiled for review, **disabled by default**, and is not a replacement for that identity. Its constructor does not read credentials or open a connection. No live API request or billable voice test was performed during implementation.

The optional route is a cascade: explicitly started Apple on-device dictation → an explicitly sent text request to the OpenAI Responses API → optional local system speech. Typed messages also work. **WebRTC, Realtime voice, streamed model audio, automatic turn detection, echo cancellation, and real-time barge-in protocol synchronization are not implemented.** Apple dictation and system speech are independent local services; the adapter never owns a host dot call.

## Contract and privacy

- Set `isEnabled = true` only after the user chooses this separate identity and API funding. Then `send(text:imageData:)` reads the user-supplied API key from Keychain. The application does not use ChatGPT tokens, account databases, dot memory, or a subscription inference entitlement.
- The sole endpoint is `https://api.openai.com/v1/responses`. HTTP redirects are rejected. Requests use `stream: true`, `store: false`, a bounded output budget, no tools, and no automatic retries.
- The default model is `gpt-5-mini`, whose official model page documents Responses, streaming, text output and image input. Audio is unsupported by this model. Account entitlement remains unverified. [Model reference](https://developers.openai.com/api/docs/models/gpt-5-mini).
- Text deltas come from actual `response.output_text.delta` or refusal events. Only `response.completed` with completed status commits the exchange. Incomplete, failed, disconnected, or cancelled streams do not become completed history. [Streaming reference](https://developers.openai.com/api/docs/guides/streaming-responses).
- History is local RAM only, bounded to 12 messages and 48 KB of text. `clearHistory()` also cancels work. An explicitly supplied PNG is included in that request only and is omitted from subsequent history; the UI must provide local preview and explicit send. There is no continuous capture. [Image input schema](https://developers.openai.com/api/docs/guides/images-vision).
- `store: false` is an API response-storage setting, **not a zero-retention guarantee**. Provider abuse monitoring and image-handling policies may still apply. [Data controls](https://developers.openai.com/api/docs/guides/your-data).
- `cancel()` cancels the owned HTTP session, retires its generation, and drops late callbacks. It cannot prove remote server computation/billing stopped, stop a ChatGPT dot, or stop host tasks.
- `SpeechOutputService` confirms local speaking through AVSpeech delegate events and requests immediate stop. It emits no fabricated amplitude. Text history records received text, not proof that audio was heard. The UI must stop local speech before dictation and never run these services against a live host call.

## Offline verification

The standalone fixture intercepts all URLSession requests with an in-memory `URLProtocol`. It never contacts OpenAI, uses only a synthetic test credential, and does not play speech. Run from the repository root:

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path /private/tmp/dots-services-modulecache \
  Sources/DotsCompanion/Services/*.swift \
  Tests/ServiceProbes/IndependentRuntimeProbe.swift \
  -o /private/tmp/dots-independent-runtime-probe
/private/tmp/dots-independent-runtime-probe
```

The fixture covers SSE formatting/bounds, streamed deltas, response identity, sequence deduplication, completion, incomplete/disconnected streams, cancellation of pending HTTP work, and default-disabled refusal before Keychain access. This verifies local transport code against fixtures. It does **not** establish account access, real provider behavior, audio latency, speech quality, speaker/Bluetooth handling, or parity with HeyClicky.
