import AppKit

/// The food bowl gets its own tiny panel rather than being drawn inside the cat's
/// window: it stays put on the floor while he walks over to it, and it can't be
/// clipped by his window moving away.
final class BowlWindow: NSPanel {
    private let bowlView = BowlView()

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 60, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true       // never in the way of a click
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = bowlView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `spot` is the bowl's centre at floor level, in screen coordinates.
    func show(at spot: CGPoint, kind: String, full: Bool, scale: Int) {
        let source = SpriteLibrary.shared.bowlSize
        let size = CGSize(width: source.width * CGFloat(scale), height: source.height * CGFloat(scale))
        // Drop it by two scale units so the bowl's base lands on the same line as
        // his paws; the sprite's outline pass puts them just below the floor.
        setFrame(CGRect(x: spot.x - size.width / 2, y: spot.y - CGFloat(scale) * 2,
                        width: size.width, height: size.height),
                 display: false)
        bowlView.frame = CGRect(origin: .zero, size: size)
        bowlView.set(kind: kind, full: full)
        if !isVisible { orderFrontRegardless() }
    }

    func hide() {
        if isVisible { orderOut(nil) }
    }
}

private final class BowlView: NSView {
    private var full = true
    private var kind = "kibble"

    func set(kind: String, full: Bool) {
        guard kind != self.kind || full != self.full else { return }
        self.kind = kind
        self.full = full
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let frames = SpriteLibrary.shared.bowlFrames(kind)
        let idx = full ? 0 : 1
        guard let image = frames.indices.contains(idx) ? frames[idx] : frames.first,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: bounds)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
