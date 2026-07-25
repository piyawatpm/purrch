import AppKit

enum ImageProviderError: LocalizedError {
    case notConfigured
    case network(String)
    case badResponse
    case noImage
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:      return "Add your API key first."
        case .network(let m):     return m
        case .badResponse:        return "The image service returned something unexpected."
        case .noImage:            return "The service didn't return an image."
        case .notImplemented(let m): return m
        }
    }
}

/// Turns a photo of a pet into a pixel-art rendering of it, posed to match the
/// companion's idle stance. Implementations may be a local stand-in or a cloud API.
protocol PetImageProvider {
    func render(photo: CGImage, poseTemplate: CGImage, species: String) async throws -> CGImage
}

// MARK: - Mock

/// A no-network stand-in: recolours the pose template so the whole upload →
/// render → apply flow can be exercised without a key or any spend.
struct MockImageProvider: PetImageProvider {
    func render(photo: CGImage, poseTemplate: CGImage, species: String) async throws -> CGImage {
        // Blow the silhouette up as if it were a real high-res generation, then
        // paint it a flat test tint so the pipeline (cut-out, fit, recolour) runs
        // end to end and the result is obviously "the custom pet".
        let scale = 8
        let w = poseTemplate.width * scale, h = poseTemplate.height * scale
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ImageProviderError.noImage }
        ctx.interpolationQuality = .none
        ctx.draw(poseTemplate, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let shape = ctx.makeImage() else { throw ImageProviderError.noImage }
        return PixelOps.tint(shape, with: RGB(226, 148, 74)) ?? shape
    }
}

// MARK: - Gemini

/// Google's Gemini image model ("nano banana"). Good at keeping a real pet's
/// face and markings when redrawing from a reference photo + pose template.
struct GeminiImageProvider: PetImageProvider {
    let apiKey: String
    private let model = "gemini-2.5-flash-image"

    func render(photo: CGImage, poseTemplate: CGImage, species: String) async throws -> CGImage {
        guard !apiKey.isEmpty else { throw ImageProviderError.notConfigured }
        guard let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        else { throw ImageProviderError.badResponse }

        let prompt = """
        Redraw the \(species) in the FIRST image as a small pixel-art game sprite. \
        Match the pose, framing, and proportions of the SECOND image (a reference silhouette): \
        full body, side three-quarter view, standing, facing right. \
        Keep the real pet's fur colours, markings, ear shape, and face. \
        Clean pixel art, limited palette, crisp hard pixels, transparent background, \
        no drop shadow, no ground line, no text, no border.
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inlineData": ["mimeType": "image/png", "data": PixelOps.pngBase64(photo)]],
                    ["inlineData": ["mimeType": "image/png", "data": PixelOps.pngBase64(poseTemplate)]],
                ]
            ]],
            "generationConfig": ["responseModalities": ["IMAGE"]],
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ImageProviderError.badResponse }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
            throw ImageProviderError.network("Gemini error \(http.statusCode). \(detail)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]]
        else { throw ImageProviderError.badResponse }

        for cand in candidates {
            guard let content = cand["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                guard let inline = (part["inlineData"] ?? part["inline_data"]) as? [String: Any],
                      let b64 = inline["data"] as? String,
                      let imgData = Data(base64Encoded: b64),
                      let img = NSImage(data: imgData)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else { continue }
                return img
            }
        }
        throw ImageProviderError.noImage
    }
}

// MARK: - OpenAI (not yet wired)

struct OpenAIImageProvider: PetImageProvider {
    let apiKey: String
    func render(photo: CGImage, poseTemplate: CGImage, species: String) async throws -> CGImage {
        throw ImageProviderError.notImplemented(
            "OpenAI isn't wired up yet — choose Gemini in the provider list for now.")
    }
}

extension PixelOps {
    static func pngBase64(_ image: CGImage) -> String {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .base64EncodedString() ?? ""
    }
}
