import AppKit

/// A transparent full-desktop layer that lets you drop a toy exactly where you
/// click. The toy sprite follows the cursor; a click places it, Esc or a
/// right-click cancels.
final class ToyPlacementOverlay {
    private var window: NSPanel?
    private var onPlace: ((CGPoint) -> Void)?
    private var priorPolicy: NSApplication.ActivationPolicy = .accessory

    /// `kind` is the toy being placed (drawn under the cursor as a preview).
    func begin(kind: String, onPlace: @escaping (CGPoint) -> Void) {
        guard window == nil else { return }
        self.onPlace = onPlace

        let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let panel = NSPanel(contentRect: bounds,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let view = PlacementView(kind: kind)
        view.frame = CGRect(origin: .zero, size: bounds.size)
        view.onClick = { [weak self] in self?.finish(place: true) }
        view.onCancel = { [weak self] in self?.finish(place: false) }
        panel.contentView = view
        window = panel

        priorPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    private func finish(place: Bool) {
        if place, let view = window?.contentView as? PlacementView {
            // convert the last cursor point (screen coords) up to the callback
            onPlace?(NSEvent.mouseLocation)
            _ = view
        }
        window?.orderOut(nil)
        window = nil
        onPlace = nil
        NSApp.setActivationPolicy(priorPolicy)
    }
}

private final class PlacementView: NSView {
    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?
    private let kind: String
    private var cursor: CGPoint = .zero
    private var tracking: NSTrackingArea?

    init(kind: String) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.activeAlways, .mouseMoved, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }  // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // a soft dim so it's clear the desktop is "armed"
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.10).cgColor)
        ctx.fill(bounds)

        // hint pill near the cursor
        let hint = "Click to place · Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: hint, attributes: attrs)
        let ts = text.size()
        let pill = CGRect(x: cursor.x + 18, y: cursor.y + 16, width: ts.width + 20, height: ts.height + 12)
        ctx.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.82).cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()
        text.draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + 6))

        // the toy preview under the cursor
        let frames = SpriteLibrary.shared.toyFrames(kind)
        if let img = frames.first {
            let scale: CGFloat = 3
            let size = SpriteLibrary.shared.toySize(kind)
            let r = CGRect(x: cursor.x - size.width * scale / 2,
                           y: cursor.y - size.height * scale / 2,
                           width: size.width * scale, height: size.height * scale)
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            ctx.draw(img, in: r)
        }
    }
}
