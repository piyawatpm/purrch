import Vision
import CoreImage
import CoreGraphics

/// On-device photo understanding: which animal is in the shot, and lifting it off
/// its background. Both run through Apple's Vision framework — no network, no cost.
enum PetVision {
    /// "cat" or "dog" if one is clearly the subject, else nil.
    static func detectSpecies(in image: CGImage) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeAnimalsRequest()
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    var best: (species: String, confidence: VNConfidence)?
                    for obs in request.results ?? [] {
                        for label in obs.labels {
                            let id = label.identifier.lowercased()
                            let species = id.contains("cat") ? "cat" : (id.contains("dog") ? "dog" : nil)
                            guard let species else { continue }
                            if best == nil || label.confidence > best!.confidence {
                                best = (species, label.confidence)
                            }
                        }
                    }
                    cont.resume(returning: best?.species)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// The main subject cut onto a transparent background, or nil if none is found.
    static func liftSubject(from image: CGImage) async -> CGImage? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    guard let result = request.results?.first else { cont.resume(returning: nil); return }
                    let buffer = try result.generateMaskedImage(
                        ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
                    let ci = CIImage(cvPixelBuffer: buffer)
                    let cg = CIContext().createCGImage(ci, from: ci.extent)
                    cont.resume(returning: cg)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
