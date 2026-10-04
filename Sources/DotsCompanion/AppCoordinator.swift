import AppKit
import SwiftUI
import Combine
import Carbon
import DotsCore

struct LocalFile: Identifiable {
    let id = UUID()
    let url: URL
    let bookmark: Data?
    var name: String { url.lastPathComponent }
}

@MainActor final class AppCoordinator: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    @Published var section = "Home"
    @Published var headline = "Your dot, within reach."
    @Published var message = "A small companion for your Mac. Your existing dot’s calls, memory, and work stay in ChatGPT."
    @Published var transcript = ""
    @Published var input = ""
    @Published var typedSummonID = UUID()
    @Published var isListening = false
    @Published var hostMayOwnMicrophone = false
    @Published var snapshot: ContextSnapshot?
    @Published var permissionStatus: PermissionStatus
    @Published var hotkeyLabels: [HotkeyAction: String] = [:]
    @Published var notes: [MemoryEntry] = []
    @Published var tasks: [TaskRecord] = []
    @Published var files: [LocalFile] = []
    @Published var holdToTalk = UserDefaults.standard.bool(forKey: "holdToTalk") {
        didSet { UserDefaults.standard.set(holdToTalk, forKey: "holdToTalk") }
    }
    @Published var locale = UserDefaults.standard.string(forKey: "dictation.locale") ?? "en-IN" {
        didSet { UserDefaults.standard.set(locale, forKey: "dictation.locale") }
    }
    @Published var pinOverlay = UserDefaults.standard.bool(forKey: "overlay.pinned") { didSet { overlay.pinned = pinOverlay } }
    @Published var testResult = "Not measured yet"
    @Published var lastShortcutStatus = "No registered shortcut received in this run."
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "System" {
        didSet { applyAppearance(); UserDefaults.standard.set(appearance, forKey: "appearance") }
    }
    let permissions = PermissionCoordinator()
    let hotkeys = HotkeyService()
    let actions = ActionGateway()
    let context = ContextService()
    let dictation = DictationService()
    lazy var overlay = OverlayController()
    private var workspace: NSWindow?
    private var statusItem: NSStatusItem?
    private var machine = SessionStateMachine(capabilities: [.openHost, .voiceEvents, .transcripts, .localActions])
    private var memory = MemoryStore()
    private var taskStore = TaskCoordinator()
    private var insertionTarget: InsertionTarget?
    private var dictationForInsertion = false
    private var activity: Task<Void, Never>?
    private var activityGeneration: UInt64 = 0
    private var localMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?
    private var lastPartial = ""
    private var annotation: AnnotationService?
    private let storeDirectory: URL
    private var holdStart: Task<Void, Never>?
    private var holdKeyDown = false
    private var isStartingDictation = false
    private var isFinalizingDictation = false
    private var dictationToken: UInt64?
    private var isCapturingSnapshot = false
    private var activeLocalTask: TaskID?
    private var hasOwnedActivity: Bool {
        isStartingDictation || isListening || isFinalizingDictation || isCapturingSnapshot ||
        activity != nil || holdStart != nil || (annotation?.activeCount ?? 0) > 0
    }

    override init() {
        permissionStatus = PermissionCoordinator().status
        storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DotsCompanion", isDirectory: true)
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.nithesh.DotsCompanion")
        if let other = existing.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(); NSApp.terminate(nil); return
        }
        applyAppearance()
        if FileManager.default.fileExists(atPath: storeDirectory.appendingPathComponent("notes.json").path) {
            do { try memory.load(from: storeDirectory.appendingPathComponent("notes.json")) } catch { message = "Local notes could not be loaded; the file was preserved." }
        }
        if FileManager.default.fileExists(atPath: storeDirectory.appendingPathComponent("tasks.json").path) {
            do { try taskStore.restore(from: storeDirectory.appendingPathComponent("tasks.json")) } catch { message = "Local task history could not be loaded; the file was preserved." }
        }
        notes = memory.entries; tasks = taskStore.records
        overlay.onPrimary = { [weak self] in self?.primaryOverlayAction() }
        overlay.onHome = { [weak self] in self?.showWorkspace() }
        overlay.onHide = { [weak self] in self?.hidePanel() }
        overlay.onStop = { [weak self] in self?.stopLocal() }
        hotkeys.onEvent = { [weak self] action, pressed in self?.handleHotkey(action, pressed: pressed) }
        do { try hotkeys.registerDefaults() } catch { message = error.localizedDescription }
        refreshHotkeys()
        setupStatusMenu()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            let consumed = MainActor.assumeIsolated {
                if let recorder = NSApp.keyWindow?.firstResponder as? RecorderButton, recorder.recording {
                    guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
                    recorder.recording = false; recorder.title = recorder.savedLabel
                    return true
                }
                // Escape in a save/open sheet retains its ordinary Cancel meaning.
                guard NSApp.modalWindow == nil, let self, self.hasOwnedActivity || self.overlay.isVisible else { return false }
                self.stopLocal(); return true
            }
            return consumed ? nil : event
        }
        // macOS only supplies global key events when appropriate Accessibility access exists.
        // The registered Stop combination remains available without that access.
        updateGlobalEscapeMonitor()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.stopLocal() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshPermissions() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshPermissions() } })
        _ = machine.beginSession()
        showWorkspace()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWorkspace(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        stopOwnedServices(); hotkeys.unregisterAll(); overlay.shutdown()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer); NotificationCenter.default.removeObserver(observer) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showWorkspace(section: String? = nil) {
        if let section { self.section = section }
        if workspace == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Dots Companion"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 810, height: 620); window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: WorkspaceView(model: self))
            if !window.setFrameUsingName("DotsWorkspace") { window.center() }
            window.setFrameAutosaveName("DotsWorkspace"); workspace = window
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        workspace?.makeKeyAndOrderFront(nil); NSApp.activate()
        refreshPermissions()
    }
    func summon() {
        if isStartingDictation || isListening || isFinalizingDictation {
            overlay.onPrimary = { [weak self] in self?.finishDictation() }
            overlay.show(title: isStartingDictation ? "Preparing local dictation" : isFinalizingDictation ? "Finishing your words" : "Listening locally",
                         detail: transcript.isEmpty ? "Local dictation is active. Stop cancels without insertion." : transcript,
                         state: isStartingDictation ? .appearing : isFinalizingDictation ? .thinking : .listening,
                         primary: isFinalizingDictation ? "Finishing…" : isStartingDictation ? "Cancel" : "Finish")
            return
        }
        if machine.state == .cancelled { _ = machine.beginSession() }
        overlay.onPrimary = { [weak self] in self?.primaryOverlayAction() }
        overlay.show(title: "Your dot, close by.", detail: "\(hotkeyLabels[.conversation] ?? "⌥ Space") · Call and work stay in ChatGPT.")
    }
    func hidePanel() { machine.hide(); overlay.hide() }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === workspace,
              let previousApp, !previousApp.isTerminated else { return }
        previousApp.activate()
    }
    func prepareLocalDictation() {
        stopOwnedServices()
        workspace?.orderOut(nil); previousApp?.activate()
        headline = "Focus a text field, then dictate"
        message = "Use \(hotkeyLabels[.dictation] ?? "⇧ ⌥ Space"). Press it again to finish. A changed field safely refuses insertion."
        overlay.onPrimary = { [weak self] in self?.beginDictation(insert: true) }
        overlay.show(title: headline, detail: message, primary: "Start dictation")
    }
    func openHost() {
        stopOwnedServices(); hostMayOwnMicrophone = true
        _ = machine.beginSession()
        emit(.hostOpening)
        overlay.show(title: "Opening ChatGPT", detail: "Choose your dot, then Call. ChatGPT owns the conversation.", state: .openingHost)
        let token = activityGeneration
        activity = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.activityGeneration { self.activity = nil } }
            guard !Task.isCancelled, token == self.activityGeneration else { return }
            do {
                let result = try await self.actions.launch(bundleID: "com.openai.codex")
                guard !Task.isCancelled, token == self.activityGeneration else { return }
                self.emit(.hostOpened)
                self.headline = result.verified ? "Continue with your dot in ChatGPT" : "Check ChatGPT"
                self.message = "Open your dot and choose Call. Dots Companion cannot observe this call or stop its tasks."
                self.overlay.update(title: self.headline, detail: "Call state is not available here. End calls and stop dot work in ChatGPT.", state: .hostOpen)
                self.recordObservedTask(title: "Open ChatGPT", result: result)
            } catch { guard token == self.activityGeneration else { return }; self.report(error) }
        }
    }
    func releaseHostVoice() { hostMayOwnMicrophone = false; message = "Local dictation is available. Start it only after the ChatGPT call has ended." }
    func primaryOverlayAction() {
        if isStartingDictation || isListening || isFinalizingDictation { finishDictation(); return }
        openHost()
    }
    private func handleHotkey(_ action: HotkeyAction, pressed: Bool) {
        if pressed { lastShortcutStatus = "Received: \(action.title) · \(hotkeys.bindings[action]?.label ?? "unassigned")" }
        if let recorder = workspace?.firstResponder as? RecorderButton, recorder.recording {
            if pressed, let binding = hotkeys.bindings[action] {
                var flags: NSEvent.ModifierFlags = []
                if binding.modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
                if binding.modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
                if binding.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
                if binding.modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                    timestamp: 0, windowNumber: workspace?.windowNumber ?? 0, context: nil,
                    characters: "", charactersIgnoringModifiers: binding.label.components(separatedBy: " ").last ?? "",
                    isARepeat: false, keyCode: UInt16(binding.keyCode)) { recorder.keyDown(with: event) }
            }
            return
        }
        switch action {
        case .conversation:
            if pressed { overlay.isVisible ? hidePanel() : summon() }
        case .typed:
            if pressed { section = "Home"; showWorkspace(); typedSummonID = UUID(); headline = "Write a local command" }
        case .dictation:
            if holdToTalk {
                if pressed {
                    guard !holdKeyDown else { return }
                    holdKeyDown = true
                    if isStartingDictation || isListening || isFinalizingDictation { return }
                    holdStart?.cancel(); holdStart = Task { [weak self] in
                        do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
                        guard !Task.isCancelled, let self, self.holdKeyDown else { return }
                        self.holdStart = nil
                        self.beginDictation(insert: true, startedByHold: true)
                    }
                } else {
                    holdKeyDown = false; holdStart?.cancel(); holdStart = nil
                    if isStartingDictation || isListening { finishDictation() }
                }
            } else if pressed {
                if isStartingDictation || isListening || isFinalizingDictation { finishDictation() }
                else { beginDictation(insert: true) }
            }
        case .stop: if pressed { stopLocal() }
        }
    }
    func beginDictation(insert: Bool, startedByHold: Bool = false) {
        guard !hostMayOwnMicrophone else {
            message = "End the call in ChatGPT, then choose ‘My ChatGPT call has ended’ before starting local dictation."
            showWorkspace(section: "Settings"); return
        }
        if isStartingDictation || isListening || isFinalizingDictation { finishDictation(); return }
        let held = startedByHold && holdKeyDown
        stopOwnedServices()
        holdKeyDown = held
        insertionTarget = insert ? try? actions.captureInsertionTarget() : nil
        dictationForInsertion = insert; transcript = ""; lastPartial = ""
        _ = machine.beginSession(); _ = machine.startTurn()
        let token = activityGeneration
        dictationToken = token; isStartingDictation = true
        configureDictation(for: token)
        overlay.onPrimary = { [weak self] in self?.stopLocal() }
        overlay.show(title: "Preparing local dictation", detail: "The microphone starts only for this dictation turn.", state: .appearing, primary: "Cancel")
        activity = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.activityGeneration { self.activity = nil } }
            guard !Task.isCancelled, token == self.activityGeneration, self.dictationToken == token,
                  !startedByHold || self.holdKeyDown else { return }
            do {
                try await self.dictation.start(localeIdentifier: self.locale)
                guard !Task.isCancelled, token == self.activityGeneration, self.dictationToken == token else { return }
                self.isStartingDictation = false
                self.isListening = true; self.emit(.listeningStarted)
                if startedByHold && !self.holdKeyDown { self.finishDictation(); return }
                self.overlay.onPrimary = { [weak self] in self?.finishDictation() }
                self.overlay.show(title: "Listening locally", detail: self.insertionTarget.map { "Destination: \($0.appName). Shortcut again to finish." } ?? "Copy-only: no verified editable field. Shortcut again to finish.", state: .listening, primary: "Finish")
                self.headline = "Listening on this Mac"; self.message = "On-device recognition · no audio goes to your dot."
            } catch {
                guard token == self.activityGeneration else { return }
                self.isStartingDictation = false; self.dictationToken = nil; self.insertionTarget = nil
                self.holdKeyDown = false; self.report(error)
            }
        }
    }
    private func finishDictation() {
        if isStartingDictation {
            // A release before startup completes cancels that generation; it cannot start later.
            stopOwnedServices(); _ = machine.cancel()
            headline = "Dictation cancelled before capture"
            message = "The shortcut was released before local dictation was ready. Hold it again to speak."
            overlay.onPrimary = { [weak self] in self?.beginDictation(insert: true) }
            overlay.show(title: headline, detail: message, state: .cancelled, primary: "Try dictation")
            return
        }
        guard isListening, !isFinalizingDictation else { return }
        dictation.finish(); isListening = false; isFinalizingDictation = true
        emit(.inputCommitted)
        overlay.onPrimary = { [weak self] in self?.stopLocal() }
        overlay.show(title: "Finishing your words", detail: "Microphone stopped. Waiting for the local transcript.", state: .thinking, primary: "Cancel")
    }
    private func configureDictation(for token: UInt64) {
        dictation.onPartial = { [weak self] value in
            guard let self, self.dictationToken == token, self.activityGeneration == token,
                  self.isListening || self.isFinalizingDictation else { return }
            self.transcript = value; self.lastPartial = value
            self.overlay.update(detail: value.isEmpty ? "Listening…" : value)
        }
        dictation.onLevel = { [weak self] value in
            guard let self, self.dictationToken == token, self.activityGeneration == token, self.isListening else { return }
            self.overlay.update(level: value)
        }
        dictation.onFinal = { [weak self] value in
            guard let self, self.dictationToken == token, self.activityGeneration == token,
                  self.isListening || self.isFinalizingDictation else { return }
            self.isListening = false; self.isFinalizingDictation = false; self.dictationToken = nil
            self.holdKeyDown = false; self.transcript = value
            if self.dictationForInsertion, let target = self.insertionTarget, !value.isEmpty {
                do {
                    let result = try self.actions.insert(text: value, into: target)
                    self.headline = result.verified ? "Dictation inserted" : "Check the destination"
                    self.message = result.summary; self.recordObservedTask(title: "Local dictation", result: result)
                } catch { self.headline = "Text kept for review"; self.message = error.localizedDescription + " Your words are available in Home." }
            } else { self.headline = value.isEmpty ? "No speech recognized" : "Your words are ready"; self.message = "Review in Home and choose Copy. No text was inserted." }
            self.insertionTarget = nil
            self.emit(.waitingForUser(self.message))
            self.overlay.onPrimary = { [weak self] in self?.showWorkspace() }
            self.overlay.show(title: self.headline, detail: self.message, state: .waitingForUser, primary: "Review text")
        }
        dictation.onError = { [weak self] value in
            guard let self, self.dictationToken == token, self.activityGeneration == token else { return }
            self.isListening = false; self.isStartingDictation = false; self.isFinalizingDictation = false
            self.dictationToken = nil; self.holdKeyDown = false; self.insertionTarget = nil
            self.headline = "Dictation unavailable"; self.message = value
            self.emit(.failed(value))
            self.overlay.onPrimary = { [weak self] in self?.showWorkspace(section: "Settings") }
            self.overlay.show(title: self.headline, detail: value, state: .permissionNeeded, primary: "Permissions")
        }
    }
    func prepareSnapshot() {
        stopOwnedServices()
        workspace?.orderOut(nil); previousApp?.activate()
        overlay.onPrimary = { [weak self] in self?.captureSnapshot() }
        overlay.show(title: "Choose a window to share", detail: "Bring it to the front. Capture previews one snapshot locally; it sends nothing.", primary: "Capture window")
    }
    func captureSnapshot() {
        guard !isCapturingSnapshot else { return }
        stopOwnedServices()
        isCapturingSnapshot = true
        let token = activityGeneration
        activity = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == self.activityGeneration { self.activity = nil; self.isCapturingSnapshot = false }
            }
            guard !Task.isCancelled, token == self.activityGeneration else { return }
            do {
                let value = try await self.context.captureForegroundWindow()
                guard !Task.isCancelled, token == self.activityGeneration else { return }
                self.snapshot = value; self.section = "Context"; self.showWorkspace()
                self.headline = "One window, one snapshot"; self.message = "Captured locally. Review it before saving or sharing in ChatGPT."
                self.overlay.hide()
            } catch { guard token == self.activityGeneration else { return }; self.report(error) }
        }
    }
    func discardSnapshot() {
        if isCapturingSnapshot { stopOwnedServices() }
        snapshot = nil; annotation?.clear(); message = "Local snapshot discarded."
    }
    func saveSnapshot() {
        guard let snapshot else { return }
        let save = NSSavePanel(); save.nameFieldStringValue = "Dots snapshot.png"; save.allowedContentTypes = [.png]
        if save.runModal() == .OK, let url = save.url {
            do { try snapshot.pngData.write(to: url, options: .atomic); message = "Saved locally. Attach this file to your dot in ChatGPT when you choose to share it." }
            catch { report(error) }
        }
    }
    func showSnapshotBoundary() {
        guard let snapshot, (0..<10).contains(Date().timeIntervalSince(snapshot.capturedAt)) else { message = "Capture a fresh snapshot first. An old window position cannot be trusted."; return }
        // This is explicitly a snapshot boundary, never a guessed model target.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String:Any]],
              let window = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == snapshot.windowID }),
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              CGRect(dictionaryRepresentation: bounds) == snapshot.frame,
              let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let targetApp = NSRunningApplication(processIdentifier: pid), !targetApp.isTerminated else {
            message = "The captured window changed. Capture again before pointing."; return
        }
        stopOwnedServices()
        workspace?.orderOut(nil); targetApp.activate()
        let token = activityGeneration
        activity = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.activityGeneration { self.activity = nil } }
            // Let explicit app activation settle before installing observers which invalidate cues.
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard !Task.isCancelled, token == self.activityGeneration,
                  self.snapshot?.id == snapshot.id, CGPreflightScreenCaptureAccess(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let current = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
                  let front = current.first(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 }),
                  (front[kCGWindowNumber as String] as? NSNumber)?.uint32Value == snapshot.windowID,
                  let latestBounds = front[kCGWindowBounds as String] as? NSDictionary,
                  CGRect(dictionaryRepresentation: latestBounds) == snapshot.frame else {
                if token == self.activityGeneration { self.message = "The window changed while returning to it. Capture again before pointing." }
                return
            }
            if self.annotation == nil { self.annotation = AnnotationService() }
            do {
                try self.annotation?.show(AnnotationOverlayCommand(contextID: snapshot.id, displayID: snapshot.displayID,
                    frame: AnnotationService.appKitRect(fromQuartz: snapshot.frame), kind: .highlight, duration: 3, text: "Captured window"))
            } catch { self.report(error) }
        }
    }
    func submitLocalCommand() {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !command.isEmpty else { return }
        switch command.lowercased() {
        case "open calculator": launchLocal(bundleID: "com.apple.calculator", title: "Open Calculator")
        case "open textedit": launchLocal(bundleID: "com.apple.TextEdit", title: "Open TextEdit")
        case "open chatgpt", "call my dot": openHost()
        case "stop": stopLocal()
        default: headline = "Continue this with your dot"; message = "This companion runs only the local commands shown below. Copy your text and use it in your dot’s conversation in ChatGPT."
        }
    }
    func launchLocal(bundleID: String, title: String) {
        stopOwnedServices(); _ = machine.beginSession(); emit(.actionStarted)
        let token = activityGeneration
        guard let session = machine.sessionID else { return }
        let record: TaskRecord
        do { record = try taskStore.create(sessionID: session, title: title, idempotencyKey: UUID().uuidString) } catch { report(error); return }
        _ = taskStore.update(record.id, generation: record.generation, state: .dispatched, progress: "Opening application")
        activeLocalTask = record.id
        persistTasks()
        activity = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == self.activityGeneration { self.activity = nil; self.activeLocalTask = nil }
            }
            guard !Task.isCancelled, token == self.activityGeneration else { return }
            do {
                let result = try await self.actions.launch(bundleID: bundleID)
                guard !Task.isCancelled, token == self.activityGeneration else { return }
                _ = self.taskStore.update(record.id, generation: record.generation, state: result.verified ? .completed : .unverified, result: result.summary, postconditionVerified: result.verified)
                self.headline = result.summary
                self.message = result.verified ? "Verified by the running application’s process identity." : "The launch was requested; its result could not be verified."
                self.emit(.actionFinished)
                self.overlay.show(title: self.headline, detail: self.message, state: result.verified ? .completed : .waitingForUser)
            } catch {
                guard token == self.activityGeneration else { return }
                _ = self.taskStore.update(record.id, generation: record.generation, state: .failed, result: error.localizedDescription); self.report(error)
            }
            self.persistTasks()
        }
    }
    func stopLocal() {
        stopOwnedServices(); _ = machine.cancel()
        persistTasks(); snapshot = nil
        headline = "Local activity stopped"
        message = "Microphone and capture are off. Stop calls, delegated tasks, and routines separately in ChatGPT. Completed actions remain."
        overlay.onPrimary = { [weak self] in self?.openHost() }
        overlay.show(title: headline, detail: "To stop your dot’s calls or tasks, use ChatGPT’s controls.", state: .cancelled)
    }
    private func stopOwnedServices() {
        // NSWorkspace may already have dispatched an app launch. Cancellation suppresses later
        // UI/effects; it cannot claim that macOS undid the launch or acknowledged stopping it.
        if let id = activeLocalTask, let record = taskStore.task(id), !record.state.isTerminal {
            _ = taskStore.update(id, generation: record.generation, state: .unverified,
                                 result: "Observation stopped. A launch already dispatched to macOS may still finish; check the application.")
            persistTasks()
        }
        activeLocalTask = nil
        activityGeneration &+= 1; activity?.cancel(); activity = nil; holdStart?.cancel(); holdStart = nil
        dictationToken = nil; isStartingDictation = false; isFinalizingDictation = false; holdKeyDown = false
        dictation.cancel(); isListening = false; isCapturingSnapshot = false
        context.cancel(); actions.cancel(); annotation?.clear(); insertionTarget = nil
    }
    func copy(_ text: String) { guard !text.isEmpty else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); message = "Copied. Paste it where you choose." }
    func refreshPermissions() {
        permissionStatus = permissions.status
        updateGlobalEscapeMonitor()
        if (isStartingDictation || isListening || isFinalizingDictation) &&
            (permissionStatus.microphone != "Allowed" || permissionStatus.speech != "Allowed") {
            stopLocal()
            headline = "Local dictation stopped"
            message = "Microphone or Speech Recognition permission is no longer allowed. Capture stopped; no text was inserted."
            overlay.update(title: headline, detail: message, state: .permissionNeeded)
        }
        if !permissionStatus.accessibility, insertionTarget != nil {
            actions.cancel(); insertionTarget = nil
            message = "Accessibility permission is unavailable. Dictation can continue for review and Copy; direct insertion is disabled."
            if isListening { overlay.update(detail: message) }
        }
        if !permissionStatus.screenCapture {
            if isCapturingSnapshot { stopOwnedServices() }
            context.cancel(); annotation?.clear(); snapshot = nil
        }
    }
    private func updateGlobalEscapeMonitor() {
        if !permissionStatus.accessibility {
            if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
            globalEscapeMonitor = nil
            return
        }
        guard globalEscapeMonitor == nil else { return }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape), !event.isARepeat else { return }
            MainActor.assumeIsolated {
                guard let self, self.hasOwnedActivity || self.overlay.isVisible else { return }
                self.stopLocal()
            }
        }
    }
    func grantMicrophone() { Task { _ = await permissions.requestMicrophone(); refreshPermissions(); if permissionStatus.microphone == "Denied" { permissions.openMicrophoneSettings() } } }
    func grantSpeech() { Task { _ = await permissions.requestSpeech(); refreshPermissions(); if permissionStatus.speech == "Denied" { permissions.openSpeechSettings() } } }
    func grantScreen() { _ = permissions.requestScreenCapture(); refreshPermissions() }
    func updateShortcut(_ action: HotkeyAction, event: NSEvent) {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let glyphs = (event.modifierFlags.contains(.control) ? "⌃ " : "") + (event.modifierFlags.contains(.option) ? "⌥ " : "") + (event.modifierFlags.contains(.shift) ? "⇧ " : "") + (event.modifierFlags.contains(.command) ? "⌘ " : "")
        let key = event.keyCode == 49 ? "Space" : event.keyCode == 53 ? "Esc" : (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        do { try hotkeys.update(action: action, binding: HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: glyphs + key)); refreshHotkeys(); message = "Shortcut saved and registered." }
        catch { report(error) }
    }
    private func refreshHotkeys() { hotkeyLabels = hotkeys.bindings.mapValues(\.label) }
    func saveNote(id: UUID? = nil, title: String, content: String) {
        do { try memory.upsert(MemoryEntry(id: id ?? UUID(), title: title, content: content)); try memory.save(to: storeDirectory.appendingPathComponent("notes.json")); notes = memory.entries }
        catch { report(error) }
    }
    func deleteNote(_ id: UUID) { memory.remove(id); do { try memory.save(to: storeDirectory.appendingPathComponent("notes.json")); notes = memory.entries } catch { report(error) } }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }
    func addFiles(_ urls: [URL]) {
        for url in urls.prefix(16) where url.isFileURL && !files.contains(where: { $0.url == url }) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            files.append(LocalFile(url: url, bookmark: bookmark))
        }
        files = Array(files.prefix(32)); message = "Files stay local. Nothing is uploaded or attached to your dot automatically."
    }
    func openFile(_ file: LocalFile) {
        let scoped = file.url.startAccessingSecurityScopedResource(); defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }
        if !NSWorkspace.shared.open(file.url) { message = "macOS could not open this file." }
    }
    func runLocalBenchmark() {
        guard !hasOwnedActivity else { message = "Finish or stop the current local activity before measuring the panel."; return }
        workspace?.orderOut(nil); previousApp?.activate()
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var samples = [Double](); var preserved = 0
        for _ in 0..<50 {
            let start = DispatchTime.now().uptimeNanoseconds
            overlay.show(title: "Local visibility probe", detail: "Testing panel presentation only; no assistant response is being timed.")
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == focusedPID { preserved += 1 }
        }
        samples.sort(); let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        testResult = String(format: "50 panel submissions · p95 %.2f ms · app focus unchanged %d/50. Measures orderFront submission, not first rendered pixel or caret preservation.", p95, preserved)
        message = testResult; overlay.hide(); showWorkspace(section: "Settings")
    }
    private func recordObservedTask(title: String, result: ActionResult) {
        guard let session = machine.sessionID else { return }
        do {
            let record = try taskStore.create(sessionID: session, title: title, idempotencyKey: result.id.uuidString)
            _ = taskStore.update(record.id, generation: record.generation, state: result.verified ? .completed : .unverified, result: result.summary, postconditionVerified: result.verified)
            persistTasks()
        } catch { message = "Task result observed; history could not be saved." }
    }
    func clearLocalHistory() {
        guard !hasOwnedActivity, taskStore.records.allSatisfy({ $0.state.isTerminal }) else {
            message = "Stop local activity before clearing its history."; return
        }
        // Commit the empty store before changing the visible history or session. A failed
        // write must preserve the old records and must not be reported as a successful reset.
        let emptyStore = TaskCoordinator()
        do {
            try emptyStore.save(to: storeDirectory.appendingPathComponent("tasks.json"))
            _ = machine.beginSession()
            taskStore = emptyStore
            tasks = []
            message = "Local activity history cleared. ChatGPT work and local files were not changed."
        } catch {
            message = "Local activity history could not be cleared. Your existing history is still available."
        }
    }
    private func persistTasks() { tasks = taskStore.records; do { try taskStore.save(to: storeDirectory.appendingPathComponent("tasks.json")) } catch { message = "Local task history could not be saved." } }
    private func emit(_ event: SessionEvent) {
        guard let session = machine.sessionID else { return }
        _ = machine.apply(.init(sessionID: session, turnID: machine.turnID, generation: machine.generation, event: event))
    }
    private func report(_ error: Error) {
        headline = "A little setup is needed"; message = error.localizedDescription; emit(.failed(message))
        overlay.onPrimary = { [weak self] in self?.showWorkspace(section: "Settings") }
        overlay.show(title: headline, detail: message, state: .error, primary: "Open settings")
    }
    private func applyAppearance() { NSApp.appearance = appearance == "System" ? nil : NSAppearance(named: appearance == "Dark" ? .darkAqua : .aqua) }
    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "circle.inset.filled", accessibilityDescription: "Dots Companion")
        let menu = NSMenu()
        for (title, selector) in [("Show companion", #selector(menuSummon)), ("Open Home", #selector(menuHome)), ("Stop local activity", #selector(menuStop)), ("Settings…", #selector(menuSettings)), ("Quit Dots Companion", #selector(menuQuit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        statusItem?.menu = menu
        // Native edit commands and keyboard quit work when the Home window is focused.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Dots Companion")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self; appMenu.addItem(settingsItem); appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Dots Companion", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem); appItem.submenu = appMenu
        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu; NSApp.mainMenu = mainMenu
    }
    @objc private func menuSummon() { summon() }
    @objc private func menuHome() { showWorkspace() }
    @objc private func menuStop() { stopLocal() }
    @objc private func menuSettings() { showWorkspace(section: "Settings") }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
