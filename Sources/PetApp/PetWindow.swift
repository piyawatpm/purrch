import AppKit

/// A borderless, non-activating panel just big enough for the cat plus room for a
/// speech bubble. It is repositioned every frame rather than spanning the desktop,
/// so the rest of the screen keeps receiving clicks normally.
final class PetWindow: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Keep him out of Mission Control's window list and off the Dock.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the current sprite frame, the speech bubble, and the heart particles, and
/// turns raw mouse events into pet / drag / throw gestures.
final class PetView: NSView {
    private let brain: PetBrain
    private let lib = SpriteLibrary.shared
    private let settings = Settings.shared

    /// Padding around the sprite, in points, leaving room for bubbles and hearts.
    static let padX: CGFloat = 40
    static let padTop: CGFloat = 56
    static let padBottom: CGFloat = 10

    var onClick: (() -> Void)?

    private var dragOffset = CGSize.zero
    private var isDragging = false
    private var dragDistance: CGFloat = 0
    private var lastDragPoint = CGPoint.zero
    private var lastDragTime = CFAbsoluteTimeGetCurrent()
    private var dragVelocity = CGVector.zero

    private struct Heart { var pos: CGPoint; var vel: CGVector; var life: Double }
    private var hearts: [Heart] = []

    init(brain: PetBrain) {
        self.brain = brain
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    private var scale: CGFloat { CGFloat(settings.scale) }
    private var spriteSize: CGSize {
        CGSize(width: CGFloat(lib.frameWidth) * scale, height: CGFloat(lib.frameHeight) * scale)
    }

    /// The sprite's rect inside this view. Also the anchor for the task popover.
    var spriteRect: CGRect {
        CGRect(origin: CGPoint(x: Self.padX, y: Self.padBottom), size: spriteSize)
    }

    /// The popover hangs off this rather than off him directly, so the speech
    /// bubble, the hearts, and his happy hop all stay visible while the list is
    /// open instead of being covered by it.
    var popoverAnchorRect: CGRect {
        var rect = spriteRect
        rect.size.height += Self.padTop - 10
        return rect
    }

    static func windowSize(scale: Int) -> CGSize {
        let lib = SpriteLibrary.shared
        return CGSize(width: CGFloat(lib.frameWidth) * CGFloat(scale) + padX * 2,
                      height: CGFloat(lib.frameHeight) * CGFloat(scale) + padTop + padBottom)
    }

    /// Where the window's bottom-left corner must sit for the cat's feet to land on
    /// `brain.position`.
    static func windowOrigin(for position: CGPoint, scale: Int) -> CGPoint {
        let lib = SpriteLibrary.shared
        let size = windowSize(scale: scale)
        let footInset = CGFloat(lib.footInset) * CGFloat(scale)
        return CGPoint(x: position.x - size.width / 2,
                       y: position.y - padBottom - footInset)
    }

    // MARK: - Drawing

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        let frame = brain.currentFrame
        let rect = spriteRect

        ctx.saveGState()
        if !brain.facingRight {
            ctx.translateBy(x: rect.midX, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -rect.midX, y: 0)
        }
        ctx.draw(frame.image, in: rect)
        ctx.restoreGState()

        ctx.setShouldAntialias(true)
        drawHearts(ctx)
        if let speech = brain.speech { drawBubble(ctx, text: speech) }
    }

    private func drawHearts(_ ctx: CGContext) {
        for heart in hearts {
            let alpha = min(1.0, heart.life)
            let size = 7.0 + (1 - heart.life) * 3
            ctx.saveGState()
            ctx.setFillColor(NSColor(calibratedRed: 0.92, green: 0.35, blue: 0.45, alpha: alpha).cgColor)
            let path = heartPath(center: heart.pos, size: size)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    private func heartPath(center: CGPoint, size: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let s = size / 2
        p.move(to: CGPoint(x: center.x, y: center.y - s))
        p.addCurve(to: CGPoint(x: center.x - s, y: center.y + s * 0.45),
                   control1: CGPoint(x: center.x - s * 0.8, y: center.y - s * 0.2),
                   control2: CGPoint(x: center.x - s, y: center.y))
        p.addArc(center: CGPoint(x: center.x - s * 0.5, y: center.y + s * 0.45),
                 radius: s * 0.5, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addArc(center: CGPoint(x: center.x + s * 0.5, y: center.y + s * 0.45),
                 radius: s * 0.5, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addCurve(to: CGPoint(x: center.x, y: center.y - s),
                   control1: CGPoint(x: center.x + s, y: center.y),
                   control2: CGPoint(x: center.x + s * 0.8, y: center.y - s * 0.2))
        p.closeSubpath()
        return p
    }

    private func drawBubble(_ ctx: CGContext, text: String) {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.10, alpha: 1),
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textSize = attributed.size()

        let padding = CGSize(width: 10, height: 6)
        let bubbleSize = CGSize(width: min(textSize.width, 150) + padding.width * 2,
                                height: textSize.height + padding.height * 2)
        let anchorX = spriteRect.midX + (brain.facingRight ? 6 : -6)
        var origin = CGPoint(x: anchorX - bubbleSize.width / 2,
                             y: spriteRect.maxY - 6)
        origin.x = min(max(origin.x, 2), bounds.width - bubbleSize.width - 2)
        let bubble = CGRect(origin: origin, size: bubbleSize)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4,
                      color: NSColor(calibratedWhite: 0, alpha: 0.35).cgColor)
        ctx.setFillColor(NSColor(calibratedWhite: 0.97, alpha: 0.97).cgColor)

        let path = CGMutablePath()
        path.addRoundedRect(in: bubble, cornerWidth: 8, cornerHeight: 8)
        // little tail pointing down at his head
        let tailX = min(max(anchorX, bubble.minX + 12), bubble.maxX - 12)
        path.move(to: CGPoint(x: tailX - 5, y: bubble.minY + 0.5))
        path.addLine(to: CGPoint(x: tailX + 1, y: bubble.minY - 6))
        path.addLine(to: CGPoint(x: tailX + 6, y: bubble.minY + 0.5))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        attributed.draw(at: CGPoint(x: bubble.minX + padding.width,
                                    y: bubble.minY + padding.height))
    }

    // MARK: - Animation of particles

    func stepParticles(dt: TimeInterval) {
        guard !hearts.isEmpty else { return }
        for i in hearts.indices {
            hearts[i].pos.x += hearts[i].vel.dx * CGFloat(dt)
            hearts[i].pos.y += hearts[i].vel.dy * CGFloat(dt)
            hearts[i].vel.dx *= 0.98
            hearts[i].life -= dt * 0.9
        }
        hearts.removeAll { $0.life <= 0 }
    }

    func burstHearts() {
        for _ in 0..<5 {
            hearts.append(Heart(
                pos: CGPoint(x: spriteRect.midX + .random(in: -8...12),
                             y: spriteRect.maxY - .random(in: 0...10)),
                vel: CGVector(dx: .random(in: -14...14), dy: .random(in: 26...46)),
                life: .random(in: 0.8...1.3)))
        }
    }

    var hasParticles: Bool { !hearts.isEmpty }

    // MARK: - Hit testing

    /// Only the cat's own pixels are clickable; everything else falls through to
    /// whatever window is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return isOnCat(local) ? self : nil
    }

    private func isOnCat(_ local: CGPoint) -> Bool {
        let rect = spriteRect
        guard rect.contains(local) else { return false }
        var px = Int((local.x - rect.minX) / scale)
        let py = Int((rect.maxY - local.y) / scale)   // sprite rows run top-down
        if !brain.facingRight { px = lib.frameWidth - 1 - px }
        guard px >= 0, px < lib.frameWidth, py >= 0, py < lib.frameHeight else { return false }
        return brain.currentFrame.opaque[py * lib.frameWidth + px]
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(spriteRect, cursor: .openHand)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragDistance = 0
        dragVelocity = .zero
        lastDragPoint = NSEvent.mouseLocation
        lastDragTime = CFAbsoluteTimeGetCurrent()
        dragOffset = CGSize(width: NSEvent.mouseLocation.x - brain.position.x,
                            height: NSEvent.mouseLocation.y - brain.position.y)
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        dragDistance += hypot(now.x - lastDragPoint.x, now.y - lastDragPoint.y)

        if !isDragging, dragDistance > 4 {
            isDragging = true
            brain.beginDrag()
            NSCursor.closedHand.set()
        }
        guard isDragging else { return }

        let dt = max(1.0 / 120, CFAbsoluteTimeGetCurrent() - lastDragTime)
        dragVelocity = CGVector(dx: (now.x - lastDragPoint.x) / dt,
                                dy: (now.y - lastDragPoint.y) / dt)
        lastDragPoint = now
        lastDragTime = CFAbsoluteTimeGetCurrent()

        brain.dragTo(CGPoint(x: now.x - dragOffset.width, y: now.y - dragOffset.height))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.arrow.set()
        if isDragging {
            brain.endDrag(throwVelocity: dragVelocity)
        } else {
            onClick?()
        }
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        NSApp.sendAction(#selector(AppDelegate.showMenuFromPet(_:)), to: nil, from: self)
    }
}
