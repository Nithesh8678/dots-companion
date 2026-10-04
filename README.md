# Dots Companion

**A little company. Right where you work.**

Dots Companion is a native macOS project built around a simple idea: an assistant should be close enough to help without taking over your desktop.

A small floating dot, a keyboard shortcut, and a natural conversation. Ask a question, think through an idea, dictate a thought, or get help with a task—then return to what you were doing.

## The experience

The interaction is designed to begin with a shortcut. The companion appears near the top of the screen, listens when invited, and keeps the conversation within reach. Its larger workspace gives messages, local activity, notes, files, and settings a place to live.

The design centers on five principles:

- **One shortcut away.** A quick path from working to talking, with configurable keyboard controls.
- **Small by default.** A compact companion that respects window focus and leaves room for your work.
- **Your context, by choice.** Deliberate window snapshots and local file references, with a clear boundary between capturing and sharing.
- **Clear feedback.** Distinct listening, thinking, speaking, and stopped states tied to what the app is actually doing.
- **Easy to stop.** Immediate cancellation of companion-owned activity and visible control over microphone use.

## A local voice companion

The local voice design combines three parts:

```text
Your voice
    ↓
Apple on-device speech recognition
    ↓
Qwen3 8B through Ollama
    ↓
Apple system speech
    ↓
A spoken reply
```

This approach puts transcription, response generation, and speech playback on the Mac. Local inference avoids per-minute API charges and uses the computer’s own memory and processing power.

Dots Companion has its own assistant identity. It does not inherit an existing ChatGPT dot’s conversations, memory, voice, or connected accounts.

## A home for the useful things

The native workspace brings together:

| Space | Purpose |
| --- | --- |
| **Home** | Conversation, typed input, and quick local actions |
| **Work** | A record of actions initiated by the companion |
| **Context** | A deliberate preview of a selected window |
| **Files** | Local references to useful documents |
| **Notes** | Thoughts worth keeping on the Mac |
| **Settings** | Shortcuts, language, appearance, and permissions |

## Built for macOS

The project uses **Swift, AppKit, and SwiftUI**, with a nonactivating `NSPanel` for the floating companion. Core Animation gives the dot its visual feedback; Apple’s Speech and AVFoundation frameworks provide the foundation for audio. ScreenCaptureKit and Accessibility support scoped context and verified interactions.

The code separates platform services from the core rules for sessions, cancellation, task state, geometry, and local persistence.

```text
Sources/
├── DotsCompanion/     Native interface and macOS services
└── DotsCore/          State, lifecycle, and persistence rules
Tests/                Core tests and service probes
Resources/            App icon, bundle metadata, and entitlements
scripts/              Development build and packaging tools
docs/                 Architecture and technical references
```

## Privacy as a design constraint

Microphone access, screen context, and desktop actions each deserve a clear purpose. The project favors explicit capture, local storage, bounded context, and visible cancellation. Notes and file references are separate from assistant memory; a screenshot preview is separate from sending an image to a model.

Credentials belong in Keychain, not source files. Host applications keep their own authentication. A successful request is never a substitute for observing the result of an action.

## Inspiration

[HeyClicky](https://www.heyclicky.com/) is an interaction reference for a companion that feels present on the desktop. Dots Companion’s interface, artwork, and implementation are independently authored. The project is not affiliated with HeyClicky or OpenAI.

---

*A companion close enough to help, quiet enough to let you work.*
