import AppKit
import QuartzCore
import DotsCore

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One small, nonactivating surface. Static states have no animation or timer.
@MainActor final class OverlayController {
    private(set) var panel: CompanionPanel
    private let dot = DotRenderer(frame: NSRect(x: 16, y: 29, width: 48, height: 48))
    private let title = NSTextField(labelWithString: "Ready when you are.")
    private let detail = NSTextField(wrappingLabelWithString: "Press your shortcut to talk to your local companion.")
    private let primary = NSButton(title: "Start talking", target: nil, action: nil)
    private let secondary = NSButton(title: "Home", target: nil, action: nil)
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    var onPrimary: (() -> Void)?
    var onHome: (() -> Void)?
    var onStop: (() -> Void)?
    var onHide: (() -> Void)?
    private var displayObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var hideWork: DispatchWorkItem?
    private var generation = 0
    private(set) var isVisible = false
    var pinned = false { didSet { UserDefaults.standard.set(pinned, forKey: "overlay.pinned") } }

    init() {
        panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 128),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let background = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 25
        background.layer?.masksToBounds = true
        panel.contentView = background
        background.addSubview(dot)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 79, y: 82, width: 268, height: 22)
        detail.font = .systemFont(ofSize: 11.5); detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 79, y: 41, width: 282, height: 37)
        [primary, secondary, stopButton].forEach { $0.bezelStyle = .rounded; $0.controlSize = .small; $0.font = .systemFont(ofSize: 11.5) }
        primary.frame = NSRect(x: 77, y: 9, width: 132, height: 27)
        secondary.frame = NSRect(x: 212, y: 9, width: 62, height: 27)
        stopButton.frame = NSRect(x: 278, y: 9, width: 62, height: 27)
        closeButton.frame = NSRect(x: 357, y: 95, width: 24, height: 24)
        closeButton.isBordered = false; closeButton.font = .systemFont(ofSize: 18)
        primary.target = self; primary.action = #selector(primaryPressed)
        secondary.target = self; secondary.action = #selector(homePressed)
        stopButton.target = self; stopButton.action = #selector(stopPressed)
        closeButton.target = self; closeButton.action = #selector(hidePressed)
        closeButton.setAccessibilityLabel("Hide companion and end local voice conversation")
        stopButton.setAccessibilityLabel("Stop activity owned by Dots Companion")
        [title, detail, primary, secondary, stopButton, closeButton].forEach { background.addSubview($0) }
        pinned = UserDefaults.standard.bool(forKey: "overlay.pinned")
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.position(reset: true) }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibility() }
        }
        refreshAccessibility()
    }
    func show(title: String, detail: String, state: SessionState = .waitingForUser, primary: String = "Start talking") {
        generation += 1; hideWork?.cancel()
        self.title.stringValue = title; self.detail.stringValue = detail; self.primary.title = primary
        dot.update(state: state)
        position(reset: !isVisible && !pinned)
        let wasVisible = isVisible; isVisible = true
        panel.orderFrontRegardless()
        guard !wasVisible else { return }
        animateOpacity(to: 1, duration: 0.20, initial: 0)
    }
    func update(title: String? = nil, detail: String? = nil, state: SessionState? = nil, level: Float? = nil) {
        if let title { self.title.stringValue = title }
        if let detail { self.detail.stringValue = detail }
        if let state { dot.update(state: state) }
        if let level { dot.setEnergy(CGFloat(level)) }
    }
    func hide() {
        guard isVisible else { return }
        generation += 1; let ticket = generation
        isVisible = false; dot.pause()
        if pinned {
            UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: "overlay.position")
        }
        animateOpacity(to: 0, duration: 0.16)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == ticket, !self.isVisible else { return }
            self.panel.orderOut(nil)
        }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.17, execute: work)
    }
    func shutdown() {
        hideWork?.cancel(); panel.orderOut(nil); dot.pause()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
    private func position(reset: Bool) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return }
        if pinned, !reset, let saved = UserDefaults.standard.array(forKey: "overlay.position") as? [Double], saved.count == 2 {
            let point = CGPoint(x: saved[0], y: saved[1])
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSRect(origin: point, size: panel.frame.size)) }) { panel.setFrameOrigin(point); return }
        }
        if !reset && isVisible { return }
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 10
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: top - panel.frame.height))
    }
    private func animateOpacity(to value: Float, duration: Double, initial: Float? = nil) {
        guard let layer = panel.contentView?.layer else { return }
        let from = (layer.presentation()?.opacity) ?? initial ?? layer.opacity
        layer.removeAnimation(forKey: "presence")
        CATransaction.begin(); CATransaction.setDisableActions(true); layer.opacity = value; CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "opacity"); animation.fromValue = from; animation.toValue = value
        animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "presence")
    }
    private func refreshAccessibility() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        panel.contentView?.layer?.backgroundColor = reduced ? NSColor.windowBackgroundColor.cgColor : nil
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { dot.pause() }
    }
    @objc private func primaryPressed() { onPrimary?() }
    @objc private func homePressed() { onHome?() }
    @objc private func stopPressed() { onStop?() }
    @objc private func hidePressed() { onHide?() }
}

@MainActor final class DotRenderer: NSView {
    private let body = CAShapeLayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private var state: SessionState = .dormant
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); wantsLayer = true
        body.path = CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 44, height: 44), transform: nil)
        body.fillColor = NSColor(calibratedRed: 0.72, green: 0.86, blue: 0.49, alpha: 1).cgColor
        body.shadowColor = NSColor.black.cgColor; body.shadowOpacity = 0.12; body.shadowRadius = 5; body.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(body)
        for (index, eye) in [leftEye, rightEye].enumerated() {
            eye.path = CGPath(roundedRect: CGRect(x: 14 + index * 13, y: 20, width: 5, height: 8), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            eye.fillColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor
            body.addSublayer(eye)
        }
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Dots companion, resting")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(state: SessionState) {
        self.state = state; pause()
        setAccessibilityLabel("Dots companion, \(state.rawValue)")
        let color: NSColor = [.error, .permissionNeeded].contains(state) ? .systemOrange : NSColor(calibratedRed: 0.72, green: 0.86, blue: 0.49, alpha: 1)
        body.fillColor = color.cgColor
        guard [.thinking, .acting, .openingHost].contains(state), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity"); pulse.fromValue = 1; pulse.toValue = 0.65; pulse.duration = 0.75; pulse.autoreverses = true; pulse.repeatCount = .infinity
        body.add(pulse, forKey: "processing")
    }
    func setEnergy(_ energy: CGFloat) {
        guard state == .listening, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let amount = min(1, max(0, energy))
        let scale = 1 + amount * 0.12
        CATransaction.begin(); CATransaction.setAnimationDuration(0.08)
        body.transform = CATransform3DMakeScale(scale, 1 / sqrt(scale), 1)
        CATransaction.commit()
    }
    func pause() { body.removeAllAnimations(); body.transform = CATransform3DIdentity }
}
