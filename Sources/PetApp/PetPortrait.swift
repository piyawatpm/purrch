import AppKit

// MARK: - Coat palette

/// The five fur tones the sprite art is built from. A photo-derived palette is
/// remapped onto every animation so the whole companion matches the user's pet,
/// not just the idle likeness.
struct CoatPalette: Equatable {
    var outline: RGB, dark: RGB, mid: RGB, light: RGB, rim: RGB
    var eye: RGB?

    var encoded: String {
        var parts = [outline.hex, dark.hex, mid.hex, light.hex, rim.hex]
        if let eye { parts.append(eye.hex) }
        return parts.joined(separator: ",")
    }

    init(outline: RGB, dark: RGB, mid: RGB, light: RGB, rim: RGB, eye: RGB? = nil) {
        self.outline = outline; self.dark = dark; self.mid = mid
        self.light = light; self.rim = rim; self.eye = eye
    }

    init?(encoded: String) {
        let p = encoded.split(separator: ",").map(String.init)
        guard p.count >= 5,
              let o = RGB(hex: p[0]), let dk = RGB(hex: p[1]), let m = RGB(hex: p[2]),
              let l = RGB(hex: p[3]), let r = RGB(hex: p[4]) else { return nil }
        self.init(outline: o, dark: dk, mid: m, light: l, rim: r,
                  eye: p.count >= 6 ? RGB(hex: p[5]) : nil)
    }

    /// The baked coat of the stock art, used as a safety net if a photo yields
    /// too few colours to sample.
    static func fallback(for species: String) -> CoatPalette {
        species == "dog"
            ? CoatPalette(outline: RGB(70, 52, 40), dark: RGB(196, 168, 128), mid: RGB(224, 200, 160),
                          light: RGB(242, 226, 196), rim: RGB(252, 244, 228))
            : CoatPalette(outline: RGB(9, 9, 13), dark: RGB(25, 25, 31), mid: RGB(37, 37, 46),
                          light: RGB(52, 52, 64), rim: RGB(110, 114, 138))
    }
}

extension RGB {
    var luma: Double { 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b) }

    func scaled(_ f: Double) -> RGB {
        func c(_ v: UInt8) -> UInt8 { UInt8(min(255, max(0, (Double(v) * f).rounded()))) }
        return RGB(c(r), c(g), c(b))
    }

    func mixed(with o: RGB, t: Double) -> RGB {
        let u = 1 - t
        func c(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(min(255, max(0, (Double(a) * u + Double(b) * t).rounded()))) }
        return RGB(c(r, o.r), c(g, o.g), c(b, o.b))
    }
}

// MARK: - Pipeline

struct PortraitResult {
    let species: String
    let idle: CGImage        // frame-sized, feet on the ground line
    let palette: CoatPalette
}

/// Photo → pixel-art idle sprite, in four steps: render, cut out, fit to the
/// sprite frame, then read the coat colours back off the finished sprite so the
/// rest of the rig can be tinted to match.
enum PortraitPipeline {
    static func run(photo: CGImage,
                    provider: PetImageProvider,
                    species: String,
                    template: CGImage,
                    frameWidth: Int, frameHeight: Int, groundRow: Int,
                    crisp: Bool = true) async throws -> PortraitResult {
        // 1. render the pet as pixel art posed like the idle silhouette
        let raw = try await provider.render(photo: photo, poseTemplate: template, species: species)

        // 2. ensure it's on transparency — trust the provider's alpha, else lift it
        var subject = raw
        if PixelOps.transparentFraction(raw) < 0.02 {
            subject = await PetVision.liftSubject(from: raw) ?? raw
        }

        // 3. tight-crop, then fit into the sprite frame with the feet on the floor
        let bbox = PixelOps.alphaBBox(subject)
            ?? CGRect(x: 0, y: 0, width: subject.width, height: subject.height)
        let cropped = subject.cropping(to: bbox) ?? subject

        let footInset = frameHeight - groundRow
        let topMargin = 2
        let maxW = Double(frameWidth - 2)
        let maxH = Double(max(1, groundRow - topMargin))
        let scale = min(maxW / Double(cropped.width), maxH / Double(cropped.height))
        let newW = Double(cropped.width) * scale
        let newH = Double(cropped.height) * scale

        guard let ctx = CGContext(data: nil, width: frameWidth, height: frameHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ImageProviderError.noImage }
        // Crisp (AI pixel art) keeps hard pixels; the free photo path downscales
        // smoothly then posterises so it reads as pixel art, not a blur.
        ctx.interpolationQuality = crisp ? .none : .high
        let xoff = (Double(frameWidth) - newW) / 2
        // Bottom-left origin: y = footInset puts the sprite's feet on the ground row.
        ctx.draw(cropped, in: CGRect(x: xoff, y: Double(footInset), width: newW, height: newH))
        guard var idle = ctx.makeImage() else { throw ImageProviderError.noImage }
        if !crisp { idle = PixelOps.posterize(idle, levels: 6) ?? idle }

        // 4. sample the coat off the finished sprite so portrait + rig agree
        let palette = extractPalette(from: idle) ?? CoatPalette.fallback(for: species)
        return PortraitResult(species: species, idle: idle, palette: palette)
    }

    /// Builds a five-tone ramp from the pet's actual tonal spread, so a grey pet
    /// reads grey and a cream pet reads cream rather than one flat colour.
    static func extractPalette(from image: CGImage) -> CoatPalette? {
        let colors = PixelOps.opaqueColors(image)
        guard colors.count >= 8 else { return nil }
        let sorted = colors.sorted { $0.luma < $1.luma }
        func at(_ p: Double) -> RGB { sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))] }
        let dark = at(0.20), mid = at(0.50), light = at(0.85)
        return CoatPalette(outline: dark.scaled(0.5),
                           dark: dark, mid: mid, light: light,
                           rim: light.mixed(with: RGB(255, 255, 255), t: 0.35))
    }
}

// MARK: - Store

/// Owns the saved custom look: the idle sprite on disk, the coat palette and the
/// on/off flag in Settings, and re-applying them to the live companion.
final class PetPortraitStore {
    static let shared = PetPortraitStore()
    private let settings = Settings.shared

    private var idleURL: URL { supportDir().appendingPathComponent("custom_idle.png") }

    func savedIdle() -> CGImage? {
        guard let data = try? Data(contentsOf: idleURL),
              let img = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return img
    }

    /// Persists a freshly generated pet and makes it the live appearance.
    func apply(_ result: PortraitResult) {
        writePNG(result.idle, to: idleURL)
        settings.customCoatPalette = result.palette
        settings.customPetEnabled = true
        settings.species = result.species                    // reloads the sheets
        SpriteLibrary.shared.setCustomPet(idle: result.idle, palette: result.palette)
        NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
    }

    /// Drops the custom look and returns to the stock cat/dog art.
    func revert() {
        settings.customPetEnabled = false
        SpriteLibrary.shared.setCustomPet(idle: nil, palette: nil)
        NotificationCenter.default.post(name: Settings.paletteChanged, object: nil)
    }

    /// Re-applies a saved custom pet at launch.
    func restore() {
        guard settings.customPetEnabled, let idle = savedIdle() else { return }
        SpriteLibrary.shared.setCustomPet(idle: idle, palette: settings.customCoatPalette)
    }

    private func supportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Purrch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePNG(_ image: CGImage, to url: URL) {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
