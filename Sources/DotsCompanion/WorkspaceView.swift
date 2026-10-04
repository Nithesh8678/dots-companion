import SwiftUI
import AppKit
import DotsCore
import UniformTypeIdentifiers

private let leaf = Color(red: 0.72, green: 0.85, blue: 0.49)

struct WorkspaceView: View {
    @ObservedObject var model: AppCoordinator
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var confirmClearHistory = false
    @State private var editingNote: UUID?
    @FocusState private var commandFocused: Bool
    private let sections = [("Home", "circle.grid.2x2"), ("Work", "checklist"), ("Context", "viewfinder"), ("Files", "paperclip"), ("Notes", "text.book.closed"), ("Settings", "slider.horizontal.3")]
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.section).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 5) { Circle().fill(leaf).frame(width: 6, height: 6); Text("LOCAL VOICE · SEPARATE ASSISTANT").font(.system(size: 9, weight: .semibold, design: .monospaced)) }.foregroundStyle(.secondary)
                }.padding(.horizontal, 34).padding(.top, 34).padding(.bottom, 22)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        switch model.section {
                        case "Work": work
                        case "Context": context
                        case "Files": files
                        case "Notes": notes
                        case "Settings": settings
                        default: home
                        }
                    }.frame(maxWidth: 760, alignment: .leading).padding(.horizontal, 34).padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: model.isListening || model.voiceMicrophoneActive ? "mic.fill" : "info.circle").foregroundStyle(model.isListening || model.voiceMicrophoneActive ? .orange : .secondary)
                    Text(model.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 22).padding(.vertical, 12).frame(minHeight: 56)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 810, minHeight: 620)
        .tint(Color.primary)
        .onChange(of: model.typedSummonID) { _, _ in commandFocused = true }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { DotFace(size: 29); Text("dots").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-1) }.padding(.top, 40).padding(.bottom, 35)
            ForEach(sections, id: \.0) { title, icon in
                Button { model.section = title } label: {
                    HStack(spacing: 10) { Image(systemName: icon).frame(width: 20); Text(title).font(.system(size: 12, weight: model.section == title ? .semibold : .regular)); Spacer() }
                    .foregroundStyle(model.section == title ? Color.primary : .secondary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(model.section == title ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.bottom, 4).accessibilityLabel("\(title) section")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("A LITTLE CLOSER.").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.tertiary)
                Button { model.toggleVoice() } label: { HStack { Text("Talk"); Spacer(); Text(model.hotkeyLabels[.conversation] ?? "Unassigned").font(.system(size: 10, design: .monospaced)) } }.buttonStyle(.plain)
                Button { model.stopLocal() } label: { HStack { Text("Stop local"); Spacer(); Text(model.hotkeyLabels[.stop] ?? "Unassigned").font(.system(size: 10, design: .monospaced)) } }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.system(size: 11)).padding(.bottom, 22)
        }.padding(.horizontal, 16).frame(width: 155).background(Color.primary.opacity(0.018))
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: 27) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Good company.\nRight where you work.").font(.system(size: 35, weight: .medium, design: .rounded)).tracking(-1.3).fixedSize(horizontal: false, vertical: true)
                    Text("One shortcut. Say what’s on your mind.\nA separate assistant, running on this Mac.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(leaf.opacity(0.12)).frame(width: 143, height: 143)
                    Circle().strokeBorder(leaf.opacity(0.25), lineWidth: 1).frame(width: 171, height: 171)
                    DotFace(size: 91).rotationEffect(.degrees(-7))
                }.frame(width: 174, height: 176).accessibilityHidden(true)
            }.padding(.top, 6)
            HStack(spacing: 12) {
                Button { model.toggleVoice() } label: { Label(model.voiceButtonTitle, systemImage: "waveform").font(.system(size: 12, weight: .semibold)).padding(.vertical, 6).padding(.horizontal, 9) }.buttonStyle(.borderedProminent)
                if model.voiceIsActive {
                    Button("End conversation") { model.stopLocal() }.buttonStyle(.bordered)
                } else {
                    Text(model.hotkeyLabels[.conversation] ?? "Set a shortcut in Settings").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Text("Pause to send. Press the shortcut during a reply to interrupt. Stop ends the conversation and turns the microphone off.").font(.system(size: 11)).foregroundStyle(.secondary)
            voiceConversation
            Divider()
            HStack(alignment: .top, spacing: 26) {
                feature("mic", title: "Your words, locally", detail: "On-device dictation into a verified text field.", action: "Set up dictation") { model.prepareLocalDictation() }
                feature("viewfinder", title: "Share deliberately", detail: "Preview one window locally. Voice cannot see your screen.", action: "Prepare snapshot") { model.prepareSnapshot() }
            }
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("OR TYPE A MESSAGE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary); Spacer(); Text("Qwen3 8B · local").font(.system(size: 10)).foregroundStyle(.tertiary) }
                HStack {
                    TextField("Ask something, or say “open calculator”", text: $model.input).textFieldStyle(.plain).font(.system(size: 13)).onSubmit { model.submitLocalCommand() }.accessibilityLabel("Message the local assistant").focused($commandFocused)
                    Button { model.submitLocalCommand() } label: { Image(systemName: "arrow.up").fontWeight(.semibold).frame(width: 22, height: 22) }.buttonStyle(.bordered).accessibilityLabel("Send to local assistant")
                }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 10) {
                    Button("Open Calculator") { model.launchLocal(bundleID: "com.apple.calculator", title: "Open Calculator") }
                    Button("Open TextEdit") { model.launchLocal(bundleID: "com.apple.TextEdit", title: "Open TextEdit") }
                    Spacer()
                    if !model.input.isEmpty { Button("Copy text") { model.copy(model.input) } }
                }.buttonStyle(.link).font(.system(size: 11))
            }
            if !model.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Local dictation", systemImage: "text.quote").font(.system(size: 12, weight: .semibold))
                    Text(model.transcript).font(.system(size: 13)).textSelection(.enabled)
                    Button("Copy transcription") { model.copy(model.transcript) }.buttonStyle(.bordered)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(leaf.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var voiceConversation: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Circle().fill(model.voiceMicrophoneActive ? Color.orange : leaf).frame(width: 6, height: 6)
                Text(model.voiceStatus).font(.system(size: 11, weight: .medium))
                Spacer()
                if !model.voiceTranscript.isEmpty || !model.voiceReply.isEmpty {
                    Button("Clear conversation") { model.clearVoiceHistory() }.buttonStyle(.link).font(.system(size: 10))
                }
            }
            if !model.voiceTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOU").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Text(model.voiceTranscript).font(.system(size: 13)).textSelection(.enabled)
                }
            }
            if !model.voiceReply.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("COMPANION").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Text(model.voiceReply).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                    Button("Copy reply") { model.copy(model.voiceReply) }.buttonStyle(.link).font(.system(size: 10))
                }
            }
            if model.voiceTranscript.isEmpty && model.voiceReply.isEmpty {
                Text("Speech and replies stay local. Conversation history lasts for this app session. Your ChatGPT dot and its memory remain separate.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(leaf.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
    }
    private func feature(_ icon: String, title: String, detail: String, action: String, run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 20)).padding(.bottom, 2)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).frame(minHeight: 36, alignment: .top)
            Button(action, action: run).buttonStyle(.link).font(.system(size: 12))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var work: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle("A clear view of what happened.", subtitle: "These are actions started and observed by this companion. Your dot’s work lives in ChatGPT.")
            if !model.tasks.isEmpty {
                Button("Clear local history…", role: .destructive) { confirmClearHistory = true }
                    .buttonStyle(.link).font(.system(size: 11))
                    .confirmationDialog("Clear local activity history?", isPresented: $confirmClearHistory) {
                        Button("Clear history", role: .destructive) { model.clearLocalHistory() }
                    } message: { Text("This removes companion activity records. It does not stop or remove your dot’s work, notes, or files. This cannot be undone.") }
            }
            if model.tasks.isEmpty { emptyState("Nothing running here", detail: "Launch a test app from Home to see a real action and its verified result.", icon: "checkmark.circle") }
            ForEach(model.tasks.reversed()) { task in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(task.title).font(.system(size: 14, weight: .semibold)); Spacer(); Text(task.state.rawValue.capitalized).font(.system(size: 10, weight: .medium)).foregroundStyle(task.state == .completed ? Color.green : Color.secondary) }
                    Text(task.result ?? task.progress).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack { Text(task.createdAt.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(String(task.id.description.prefix(8))).fontDesign(.monospaced) }.font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(17).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            Divider()
            Text("Routines and integrations").font(.system(size: 15, weight: .semibold))
            Text("Manage recurring work, connected accounts, and follow-ups with your existing dot in ChatGPT. This companion has no synchronized task feed or scheduler.").font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Manage in ChatGPT ↗") { model.openHost() }.buttonStyle(.bordered)
        }
    }
    private var context: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle("Only what you choose to share.", subtitle: "One foreground window. A local preview. No continuous screen capture.")
            if let snapshot = model.snapshot {
                Image(nsImage: snapshot.image).resizable().scaledToFit().frame(maxHeight: 330).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
                HStack { Label(snapshot.appName, systemImage: "macwindow"); Spacer(); Text(snapshot.capturedAt.formatted(date: .omitted, time: .standard)) }.font(.system(size: 12)).foregroundStyle(.secondary)
                Text("LOCAL SNAPSHOT · NOT SENT").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                HStack {
                    Button("Save PNG…") { model.saveSnapshot() }.buttonStyle(.borderedProminent)
                    Button("Show window boundary") { model.showSnapshotBoundary() }.buttonStyle(.bordered)
                    Button("Discard") { model.discardSnapshot() }.buttonStyle(.bordered)
                }
                Text("Review for private information before attaching the saved image in ChatGPT. The boundary is shown only for a fresh, unchanged window; it is not an AI-generated instruction.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                emptyState("Your screen stays yours", detail: "Prepare a snapshot, focus the window you want, then click Capture window in the companion.", icon: "viewfinder")
                Button("Prepare snapshot") { model.prepareSnapshot() }.buttonStyle(.borderedProminent)
            }
        }
    }
    private var files: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle("Keep the useful things close.", subtitle: "Files added here are local references. They are not uploaded or attached to ChatGPT.")
            Button("Add local files…") { model.chooseFiles() }.buttonStyle(.borderedProminent)
            if model.files.isEmpty { emptyState("Drop a file here", detail: "Or choose a file above. Local references last for this app session.", icon: "paperclip") }
            ForEach(model.files) { file in
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 3) { Text(file.name).font(.system(size: 13, weight: .medium)); Text("Local · not shared").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer(); Button("Open") { model.openFile(file) }; Button { model.files.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark") }.accessibilityLabel("Remove local file reference")
                }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }.frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers.prefix(16) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in guard let url else { return }; Task { @MainActor in model.addFiles([url]) } }
            }; return true
        }
    }
    private var notes: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle("A few things worth keeping.", subtitle: "Private notes saved on this Mac. They are separate from your dot’s memory and are never sent automatically.")
            VStack(alignment: .leading, spacing: 10) {
                TextField("Note title", text: $noteTitle).textFieldStyle(.roundedBorder)
                TextEditor(text: $noteBody).font(.system(size: 13)).frame(height: 84).padding(5).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.13)))
                HStack {
                    Button(editingNote == nil ? "Save local note" : "Save changes") { model.saveNote(id: editingNote, title: noteTitle, content: noteBody); noteTitle = ""; noteBody = ""; editingNote = nil }.buttonStyle(.borderedProminent).disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if editingNote != nil { Button("Cancel edit") { editingNote = nil; noteTitle = ""; noteBody = "" } }
                }
            }
            ForEach(model.notes) { note in
                VStack(alignment: .leading, spacing: 9) {
                    Text(note.title.isEmpty ? "Untitled note" : note.title).font(.system(size: 14, weight: .semibold))
                    Text(note.content).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button("Edit") { editingNote = note.id; noteTitle = note.title; noteBody = note.content }
                        Button("Copy") { model.copy(note.content) }
                        Spacer(); Button("Remove", role: .destructive) { model.deleteNote(note.id) }
                    }.font(.system(size: 11)).buttonStyle(.link)
                }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageTitle("Make yourself at home.", subtitle: "Small controls. Clear ownership.")
            settingGroup("Your assistant") {
                HStack { DotFace(size: 35); VStack(alignment: .leading, spacing: 5) { Text("Local voice companion").font(.system(size: 13, weight: .semibold)); Text("Qwen3 8B · Ollama · no API charges").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer() }
                Text("Apple on-device recognition turns speech into text. Qwen3 replies on this Mac, and Apple’s system voice reads the answer. The microphone pauses during playback. The shortcut interrupts; Stop ends the session. The local model uses memory and battery while running.").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Requires an installed Ollama and qwen3:8b model. No automatic downloads or cloud fallback. Conversation history stays in memory until you clear it or quit. This is separate from your existing ChatGPT dot.").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Open my existing dot in ChatGPT ↗") { model.openHost() }.buttonStyle(.link).font(.system(size: 11))
                if model.hostMayOwnMicrophone { Button("My ChatGPT call has ended") { model.releaseHostVoice() }.buttonStyle(.bordered) }
            }
            settingGroup("Shortcuts") {
                ForEach(HotkeyAction.allCases, id: \.rawValue) { action in
                    HStack { Text(action.title).font(.system(size: 12)); Spacer(); ShortcutRecorder(label: model.hotkeyLabels[action] ?? "Unassigned") { model.updateShortcut(action, event: $0) }.frame(width: 170, height: 27) }
                }
                Toggle("Hold shortcut for dictation", isOn: $model.holdToTalk).font(.system(size: 12))
                Text(model.lastShortcutStatus).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Text("Click a binding, then press a combination. Known system and exclusive app conflicts keep the previous shortcut. Other apps’ shared shortcuts may not be discoverable and can be overridden; choose a combination you do not use elsewhere. Escape stops local work while this app is focused; the registered Stop shortcut works globally.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            settingGroup("Permissions · requested only when you choose") {
                permissionRow("Microphone", detail: "During voice conversation or dictation", status: model.permissionStatus.microphone) { model.grantMicrophone() }
                permissionRow("Speech Recognition", detail: "On-device model required; no cloud fallback", status: model.permissionStatus.speech) { model.grantSpeech() }
                permissionRow("Screen Recording", detail: "One window snapshot, with local preview", status: model.permissionStatus.screenCapture ? "Allowed" : "Not allowed") { model.grantScreen() }
                permissionRow("Accessibility", detail: "Verify a text field before insertion", status: model.permissionStatus.accessibility ? "Allowed" : "Not allowed") { model.permissions.openAccessibilitySettings() }
                Button("Refresh permissions") { model.refreshPermissions() }.buttonStyle(.link).font(.system(size: 11))
            }
            settingGroup("Feel & language") {
                Picker("Appearance", selection: $model.appearance) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }.font(.system(size: 12))
                Picker("Dictation language", selection: $model.locale) { Text("English · India").tag("en-IN"); Text("English · US").tag("en-US"); Text("Tamil · India").tag("ta-IN"); Text("Hindi · India").tag("hi-IN") }.font(.system(size: 12))
                Text("Availability depends on the installed on-device speech model. Unsupported languages refuse capture. Code switching is not verified.").font(.system(size: 10)).foregroundStyle(.secondary)
                Toggle("Remember companion position", isOn: $model.pinOverlay).font(.system(size: 12))
                Text("Move the companion by dragging its background. Reduce Motion and Reduce Transparency follow macOS.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            settingGroup("Local diagnostics") {
                Text(model.testResult).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Measure passive panel submissions") { model.runLocalBenchmark() }.buttonStyle(.bordered)
                Text("Development build · ad-hoc signed · not notarized. No telemetry, background helper, or login item. Screen and microphone are idle when unused.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    private func permissionRow(_ title: String, detail: String, status: String, action: @escaping () -> Void) -> some View {
        HStack { VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .medium)); Text(detail).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); Text(status).font(.system(size: 10)).foregroundStyle(.secondary); Button("Set up", action: action).font(.system(size: 11)) }
    }
    private func settingGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) { Text(title).font(.system(size: 14, weight: .semibold)); content() }.padding(18).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }
    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.system(size: 28, weight: .medium, design: .rounded)).tracking(-0.8); Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4) }
    }
    private func emptyState(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary); Text(title).font(.system(size: 17, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340) }.frame(maxWidth: .infinity).padding(.vertical, 45).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DotFace: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(leaf.gradient).shadow(color: .black.opacity(0.10), radius: size * 0.12, y: size * 0.06)
            HStack(spacing: size * 0.18) {
                Capsule().fill(Color(red: 0.12, green: 0.16, blue: 0.08)).frame(width: size * 0.085, height: size * 0.16)
                Capsule().fill(Color(red: 0.12, green: 0.16, blue: 0.08)).frame(width: size * 0.085, height: size * 0.16)
            }.offset(y: size * 0.015)
        }.frame(width: size, height: size).accessibilityLabel("Dots companion")
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let onRecord: (NSEvent) -> Void
    func makeNSView(context: Context) -> RecorderButton { let button = RecorderButton(); button.onRecord = onRecord; return button }
    func updateNSView(_ button: RecorderButton, context: Context) { button.savedLabel = label; if !button.recording { button.title = label }; button.onRecord = onRecord }
}
final class RecorderButton: NSButton {
    var onRecord: ((NSEvent) -> Void)?
    var savedLabel = ""
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() { super.init(frame: .zero); bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 11, weight: .medium); target = self; action = #selector(begin) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func begin() { recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        recording = false; title = savedLabel; onRecord?(event)
    }
    override func resignFirstResponder() -> Bool { recording = false; title = savedLabel; return super.resignFirstResponder() }
}
