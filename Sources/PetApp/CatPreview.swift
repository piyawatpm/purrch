import AppKit
import SwiftUI

/// A small live preview of the cat with the current palette and collar, used in
/// the settings window so customisation choices are visible as you make them.
struct CatPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CatPreviewView { CatPreviewView() }
    func updateNSView(_ view: CatPreviewView, context: Context) { view.refresh() }
}

final class CatPreviewView: NSView {
    private let lib = SpriteLibrary.shared
    private var frameIndex = 0
    private var timer: Timer?
    /// Cycles a few gentle poses so the preview feels alive without being busy.
    private let cycle: [PetState] = [.idle, .idle, .sit, .groom, .idle, .loaf]
    private var cycleIndex = 0
    private var elapsed: TimeInterval = 0
    private var poseHold: TimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(paletteChanged),
            name: Settings.paletteChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { start() } else { timer?.invalidate() }
    }

    private func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var pose: PetState { cycle[cycleIndex % cycle.count] }

    private func step() {
        let clip = lib.clip(pose)
        frameIndex = (frameIndex + 1) % max(1, clip.frames.count)
        elapsed += 1.0 / 12.0
        poseHold += 1.0 / 12.0
        if poseHold > 3.2 {           // move to the next pose every few seconds
            poseHold = 0
            cycleIndex += 1
            frameIndex = 0
        }
        needsDisplay = true
    }

    @objc private func paletteChanged() {
        lib.applyPalette()
        needsDisplay = true
    }

    func refresh() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // soft rounded backdrop
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.5, alpha: 0.10).setFill()
        bg.fill()

        let clip = lib.clip(pose)
        let frame = clip.frames[min(frameIndex, clip.frames.count - 1)]
        let scale = max(2, Int(min(bounds.width, bounds.height) / CGFloat(lib.frameHeight)) - 1)
        let w = CGFloat(lib.frameWidth * scale)
        let h = CGFloat(lib.frameHeight * scale)
        let rect = CGRect(x: (bounds.width - w) / 2,
                          y: (bounds.height - h) / 2,
                          width: w, height: h)
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(frame.image, in: rect)
    }
}
