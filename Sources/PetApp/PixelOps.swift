import CoreGraphics
import Foundation

/// Small pixel-buffer helpers for the portrait pipeline. Everything works on
/// straight RGBA8 with interpolation off so pixel art stays crisp, and mirrors
/// the top-down buffer convention used elsewhere (row 0 is the top row).
enum PixelOps {
    /// Draws an image into an RGBA8 buffer we can read and rewrite.
    static func buffer(_ image: CGImage) -> (px: [UInt8], w: Int, h: Int)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (px, w, h) : nil
    }

    static func image(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Repaints every sufficiently-opaque pixel one colour, keeping the alpha
    /// shape. Used by the mock renderer to stand in for a real generation.
    static func tint(_ image: CGImage, with c: RGB) -> CGImage? {
        guard let buf = buffer(image) else { return nil }
        var px = buf.px
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 20 {
            px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b
        }
        return Self.image(px, buf.w, buf.h)
    }

    /// Snaps each colour channel to `levels` steps — a limited-palette, pixel-art
    /// feel when turning a real photo into a sprite.
    static func posterize(_ image: CGImage, levels: Int) -> CGImage? {
        guard let buf = buffer(image) else { return nil }
        var px = buf.px
        let step = 255.0 / Double(max(1, levels - 1))
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 20 {
            px[i]     = UInt8(min(255, (Double(px[i]) / step).rounded() * step))
            px[i + 1] = UInt8(min(255, (Double(px[i + 1]) / step).rounded() * step))
            px[i + 2] = UInt8(min(255, (Double(px[i + 2]) / step).rounded() * step))
        }
        return Self.image(px, buf.w, buf.h)
    }

    /// The tight bounding box of the opaque pixels, in top-left pixel coords.
    static func alphaBBox(_ image: CGImage, threshold: UInt8 = 20) -> CGRect? {
        guard let (px, w, h) = buffer(image) else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where px[row + x * 4 + 3] > threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Fraction of the image that is (near-)transparent — a cheap way to tell a
    /// cut-out sprite from a photo with an opaque background.
    static func transparentFraction(_ image: CGImage) -> Double {
        guard let (px, w, h) = buffer(image), w * h > 0 else { return 0 }
        var t = 0
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] < 16 { t += 1 }
        return Double(t) / Double(w * h)
    }

    /// Every solidly-opaque pixel's colour, for palette sampling.
    static func opaqueColors(_ image: CGImage, threshold: UInt8 = 200) -> [RGB] {
        guard let (px, _, _) = buffer(image) else { return [] }
        var out: [RGB] = []
        out.reserveCapacity(px.count / 8)
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > threshold {
            out.append(RGB(px[i], px[i + 1], px[i + 2]))
        }
        return out
    }

    /// Nearest-neighbour enlarge, for crisp previews of a small sprite.
    static func upscale(_ image: CGImage, factor: Int) -> CGImage {
        let w = image.width * factor, h = image.height * factor
        guard factor > 1,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// High-quality downscale so photos stay small before they're sent to an API.
    static func fit(_ image: CGImage, maxSide: Int) -> CGImage {
        let w = image.width, h = image.height
        let m = max(w, h)
        guard m > maxSide else { return image }
        let s = Double(maxSide) / Double(m)
        let nw = max(1, Int(Double(w) * s)), nh = max(1, Int(Double(h) * s))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? image
    }
}
