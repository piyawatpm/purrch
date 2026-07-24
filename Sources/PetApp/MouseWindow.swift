import AppKit

/// The mouse toy's own click-through panel, like the food bowl. It scampers on
/// the floor while the cat hunts it.
final class MouseWindow: NSPanel {
    private let view = MouseView()

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 40, height: 30),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `spot` is the mouse's centre at floor level. `facingRight` flips the sprite,
    /// which is drawn facing left.
    func show(at spot: CGPoint, kind: String, running: Bool, facingRight: Bool, scale: Int) {
        let src = SpriteLibrary.shared.toySize(kind)
        let size = CGSize(width: src.width * CGFloat(scale), height: src.height * CGFloat(scale))
        setFrame(CGRect(x: spot.x - size.width / 2, y: spot.y - CGFloat(scale),
                        width: size.width, height: size.height), display: false)
        view.frame = CGRect(origin: .zero, size: size)
        view.update(kind: kind, running: running, facingRight: facingRight)
        if !isVisible { orderFrontRegardless() }
    }

    func hide() { if isVisible { orderOut(nil) } }
}

private final class MouseView: NSView {
    private var running = false
    private var facingRight = false
    private var kind = "mouse"

    func update(kind: String, running: Bool, facingRight: Bool) {
        guard kind != self.kind || running != self.running || facingRight != self.facingRight else { return }
        self.kind = kind
        self.running = running
        self.facingRight = facingRight
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let frames = SpriteLibrary.shared.toyFrames(kind)
        let idx = running ? 1 : 0
        guard let image = frames.indices.contains(idx) ? frames[idx] : frames.first,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        // The sprite faces left; flip when it's running to the right.
        if facingRight {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        ctx.draw(image, in: bounds)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
