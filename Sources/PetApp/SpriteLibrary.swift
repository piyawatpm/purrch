import AppKit

enum PetState: String, CaseIterable {
    case idle, walk, sit, groom, sleep, drag, fall, happy, eat
    case land, dizzy, stretch, yawn, scratch, loaf, run, wiggle
    case love, angry, curious, surprise, purr
    case flop, rollover, arch, beg, pounce, sniff, play, knead, blep, chatter, rub
    case stargaze, bellyplay, jump
}

/// One frame plus a per-pixel opacity mask, so clicks can be tested against the
/// cat's actual silhouette instead of his bounding box.
struct SpriteFrame {
    let image: CGImage
    let opaque: [Bool]      // row-major, row 0 = top
}

struct AnimationClip {
    let frames: [SpriteFrame]
    let frameDuration: TimeInterval
}

struct RGB: Equatable {
    var r: UInt8, g: UInt8, b: UInt8

    /// Parses "#RRGGBB". Returns nil for anything else.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        r = UInt8((value >> 16) & 0xFF)
        g = UInt8((value >> 8) & 0xFF)
        b = UInt8(value & 0xFF)
    }

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { (self.r, self.g, self.b) = (r, g, b) }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// A darker companion tone, used for the shaded edge of the eye.
    func shaded(_ factor: Double) -> RGB {
        RGB(UInt8(Double(r) * factor), UInt8(Double(g) * factor), UInt8(Double(b) * factor))
    }

    func matches(_ other: RGB, tolerance: Int = 8) -> Bool {
        abs(Int(r) - Int(other.r)) <= tolerance
            && abs(Int(g) - Int(other.g)) <= tolerance
            && abs(Int(b) - Int(other.b)) <= tolerance
    }
}

/// Loads the sheets produced by tools/spritegen.py and applies the user's palette.
///
/// The PNGs ship with fixed placeholder colours for the eyes and inner ears; those
/// act as keys that get remapped whenever the user picks a new colour, so
/// customisation costs one pass over the sheets rather than a redraw per frame.
final class SpriteLibrary {
    static let shared = SpriteLibrary()

    /// Placeholder colours written by the generator.
    private enum Key {
        static let eye = RGB(222, 198, 78)
        static let eyeShadow = RGB(156, 132, 44)
        static let innerEar = RGB(84, 52, 62)
        static let collar = RGB(46, 40, 64)
        static let bell = RGB(206, 176, 88)
        static let bandana = RGB(180, 72, 72)
    }

    let collarStyles: [String]

    let frameWidth: Int
    let frameHeight: Int
    /// Row in the sprite where the floor sits, measured from the top.
    let groundRow: Int

    private var sheets: [PetState: (image: CGImage, frameCount: Int, frameDuration: TimeInterval)] = [:]
    private var clips: [PetState: AnimationClip] = [:]

    /// How far his artwork actually reaches from the centre of the canvas, in
    /// sprite pixels. Idle and walk run tail-tip to whisker-tip across the full
    /// frame, so this is what "fully on screen" has to be measured against.
    private(set) var contentHalfWidth: CGFloat = 20

    /// Bowls, keyed by food name; each is [full, empty]. Drawn in its own window.
    private(set) var bowls: [String: [CGImage]] = [:]
    private(set) var bowlKinds: [String] = []
    private(set) var bowlSize = CGSize(width: 15, height: 10)

    /// Toy frames keyed by kind (mouse | ball | feather).
    private(set) var toyFrames: [String: [CGImage]] = [:]
    private(set) var toySizes: [String: CGSize] = [:]
    var mouseFrames: [CGImage] { toyFrames["mouse"] ?? [] }
    var mouseSize: CGSize { toySizes["mouse"] ?? CGSize(width: 16, height: 12) }

    /// Distance in sprite pixels from the bottom of the canvas up to the floor line.
    var footInset: Int { frameHeight - groundRow }

    private init() {
        struct Manifest: Decodable {
            struct Anim: Decodable { let frames: Int; let msPerFrame: Double }
            let frameWidth: Int, frameHeight: Int, ground: Int
            let animations: [String: Anim]
            let collarStyles: [String]?
        }

        guard let url = Bundle.module.url(forResource: "sprites", withExtension: "json",
                                          subdirectory: "Resources/Sprites"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            fatalError("sprites.json missing from the app bundle — run tools/spritegen.py")
        }

        frameWidth = manifest.frameWidth
        frameHeight = manifest.frameHeight
        groundRow = manifest.ground
        collarStyles = manifest.collarStyles ?? ["bell"]
        frameInfo = manifest.animations.mapValues { ($0.frames, $0.msPerFrame / 1000.0) }

        loadSheets(style: Settings.shared.collarStyle)
        loadBowls()
        loadMouse()
        applyPalette()
    }

    private var frameInfo: [String: (frames: Int, dur: TimeInterval)] = [:]
    private(set) var loadedStyle = ""

    /// Loads the body sheets for a collar style. A missing style falls back to bell.
    func loadSheets(style rawStyle: String) {
        let style = collarStyles.contains(rawStyle) ? rawStyle : "bell"
        sheets.removeAll()
        for state in PetState.allCases {
            guard let info = frameInfo[state.rawValue],
                  let url = sheetURL(style: style, anim: state.rawValue) ?? sheetURL(style: "bell", anim: state.rawValue),
                  let sheet = NSImage(contentsOf: url)?
                      .cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                fatalError("sprite sheet '\(style)__\(state.rawValue).png' missing from the app bundle")
            }
            sheets[state] = (sheet, info.frames, info.dur)
        }
        loadedStyle = style
    }

    private func sheetURL(style: String, anim: String) -> URL? {
        Bundle.module.url(forResource: "\(style)__\(anim)", withExtension: "png",
                          subdirectory: "Resources/Sprites")
    }

    private func loadBowls() {
        for kind in ["kibble", "fish", "treat", "milk"] {
            guard let url = Bundle.module.url(forResource: "bowl_\(kind)", withExtension: "png",
                                              subdirectory: "Resources/Sprites"),
                  let sheet = NSImage(contentsOf: url)?
                      .cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { continue }
            let w = sheet.width / 2
            bowlSize = CGSize(width: w, height: sheet.height)
            let frames = (0..<2).compactMap {
                sheet.cropping(to: CGRect(x: $0 * w, y: 0, width: w, height: sheet.height))
            }
            if frames.count == 2 { bowls[kind] = frames; bowlKinds.append(kind) }
        }
    }

    func bowlFrames(_ kind: String) -> [CGImage] {
        bowls[kind] ?? bowls["kibble"] ?? []
    }

    private func loadMouse() {
        for (kind, file) in [("mouse", "mouse"), ("ball", "toy_ball"), ("feather", "toy_feather")] {
            guard let url = Bundle.module.url(forResource: file, withExtension: "png",
                                              subdirectory: "Resources/Sprites"),
                  let sheet = NSImage(contentsOf: url)?
                      .cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { continue }
            let w = sheet.width / 2
            toySizes[kind] = CGSize(width: w, height: sheet.height)
            toyFrames[kind] = (0..<2).compactMap {
                sheet.cropping(to: CGRect(x: $0 * w, y: 0, width: w, height: sheet.height))
            }
        }
    }

    func toyFrames(_ kind: String) -> [CGImage] { toyFrames[kind] ?? toyFrames["mouse"] ?? [] }
    func toySize(_ kind: String) -> CGSize { toySizes[kind] ?? CGSize(width: 16, height: 12) }

    /// All animation names, in a friendly order for the tester.
    var animationNames: [String] { PetState.allCases.map { $0.rawValue } }

    func clip(_ state: PetState) -> AnimationClip {
        clips[state] ?? clips[.idle]!
    }

    // MARK: - Palette

    /// Rebuilds every clip from the source sheets using the colours in Settings.
    func applyPalette() {
        let settings = Settings.shared
        // Reload the body sheets if the collar style changed since last time.
        if settings.collarStyle != loadedStyle { loadSheets(style: settings.collarStyle) }

        let eye = RGB(hex: settings.eyeColorHex) ?? RGB(hex: Settings.DefaultColor.eye)!
        let ear = RGB(hex: settings.innerEarColorHex) ?? RGB(hex: Settings.DefaultColor.innerEar)!
        let collar = RGB(hex: settings.collarColorHex) ?? RGB(hex: Settings.DefaultColor.collar)!
        let bell = RGB(hex: settings.bellColorHex) ?? RGB(hex: Settings.DefaultColor.bell)!
        let map: [(from: RGB, to: RGB)] = [
            (Key.eye, eye),
            (Key.eyeShadow, eye.shaded(0.70)),
            (Key.innerEar, ear),
            (Key.collar, collar),
            (Key.bell, bell),
            (Key.bandana, collar),        // bandana cloth follows the collar colour
        ]

        for (state, sheet) in sheets {
            let recoloured = Self.recolour(sheet.image, map: map) ?? sheet.image
            var frames: [SpriteFrame] = []
            for i in 0..<sheet.frameCount {
                let rect = CGRect(x: i * frameWidth, y: 0, width: frameWidth, height: frameHeight)
                guard let cropped = recoloured.cropping(to: rect) else { continue }
                frames.append(SpriteFrame(image: cropped, opaque: Self.opacityMask(cropped)))
            }
            clips[state] = AnimationClip(frames: frames, frameDuration: sheet.frameDuration)
        }
        measureContentExtent()
    }

    /// Walks the opacity masks once to find the widest occupied column. Recolouring
    /// never touches alpha, so this is stable across palette changes.
    private func measureContentExtent() {
        var minCol = frameWidth
        var maxCol = -1
        for clip in clips.values {
            for frame in clip.frames {
                for y in 0..<frameHeight {
                    let row = y * frameWidth
                    for x in 0..<frameWidth where frame.opaque[row + x] {
                        if x < minCol { minCol = x }
                        if x > maxCol { maxCol = x }
                    }
                }
            }
        }
        guard minCol <= maxCol else { return }
        let centre = CGFloat(frameWidth) / 2
        contentHalfWidth = max(centre - CGFloat(minCol), CGFloat(maxCol + 1) - centre)
    }

    /// Swaps key colours for user-chosen ones. Matching is tolerant by a few levels
    /// because PNG decoding can shift channel values slightly.
    private static func recolour(_ image: CGImage, map: [(from: RGB, to: RGB)]) -> CGImage? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        let drew = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }

        for i in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[i + 3] > 200 else { continue }   // skip the antialiased fringe
            let here = RGB(pixels[i], pixels[i + 1], pixels[i + 2])
            for entry in map where here.matches(entry.from) {
                pixels[i] = entry.to.r
                pixels[i + 1] = entry.to.g
                pixels[i + 2] = entry.to.b
                break
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// Renders the alpha channel into a bitmap once, so hit-testing is a pair of
    /// array lookups rather than per-click image work.
    private static func opacityMask(_ image: CGImage) -> [Bool] {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        // A bitmap context's buffer is laid out top-down even though its drawing
        // origin is bottom-left, so row 0 here is the sprite's top row.
        guard drew else { return [Bool](repeating: true, count: w * h) }
        return (0..<(w * h)).map { pixels[$0 * 4 + 3] > 40 }
    }
}
