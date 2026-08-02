import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "make it look like my pet" flow: pick a photo, an image model redraws it
/// as the companion's idle sprite, and its colours are pulled onto the rest of
/// the rig. Reachable from Settings → Look.
struct PortraitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PortraitModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    providerSection
                    photoSection
                    if model.sourceImage != nil { speciesSection }
                    resultSection
                    if let error = model.errorText { errorBanner(error) }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Make it look like my pet").font(.system(size: 15, weight: .semibold))
            Text("Upload a photo — an AI redraws your pet as the companion, and the whole rig takes on its colours.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    // MARK: sections

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sharper look — optional").font(.system(size: 12, weight: .semibold))
            Picker("Engine", selection: $model.provider) {
                Text("Gemini").tag("gemini")
                Text("OpenAI").tag("openai")
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: model.provider) { _, _ in model.reloadKey() }

            SecureField("API key — leave empty for the free version", text: $model.apiKey)
                .textFieldStyle(.roundedBorder)
            Text(model.apiKey.isEmpty
                 ? "No key needed — you'll get a free version made right here on your Mac from the photo. Add a Gemini key for a sharper, AI-drawn look (a few cents per image)."
                 : "Stored securely in your Keychain. You pay the provider a few cents per image.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your pet's photo").font(.system(size: 12, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                thumbnail(model.sourceImage, side: 92, crisp: false)
                VStack(alignment: .leading, spacing: 6) {
                    Button(model.sourceImage == nil ? "Choose photo…" : "Choose another…") {
                        model.choosePhoto()
                    }
                    if let d = model.detected {
                        Label("Looks like a \(d)", systemImage: d == "dog" ? "dog.fill" : "cat.fill")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("A clear, front-or-side photo with the whole pet in frame works best.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Species").font(.system(size: 12, weight: .semibold))
            Picker("Species", selection: $model.species) {
                Text("Cat").tag("cat"); Text("Dog").tag("dog")
            }
            .pickerStyle(.segmented).labelsHidden()
            Text("Sets which rig your pet's colours ride on. We guessed from the photo — change it if we're wrong.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result").font(.system(size: 12, weight: .semibold))
                if model.busy { ProgressView().controlSize(.small).padding(.leading, 4) }
                Spacer()
                if !model.status.isEmpty {
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05))
                    thumbnail(model.resultImage, side: 120, crisp: true)
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 6) {
                    if let palette = model.resultPalette { swatches(palette) }
                    Text(model.resultImage == nil
                         ? "Generate to see your pet in the idle pose."
                         : "This becomes the resting look; movement uses the rig in these colours.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            Button {
                model.generate()
            } label: {
                Label(model.apiKey.isEmpty ? "Make it (free)" : "Generate", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.sourceImage == nil || model.busy)
        }
    }

    private func swatches(_ p: CoatPalette) -> some View {
        HStack(spacing: 4) {
            ForEach(Array([p.outline, p.dark, p.mid, p.light, p.rim].enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.sRGB, red: Double(c.r)/255, green: Double(c.g)/255, blue: Double(c.b)/255))
                    .frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.12)))
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
    }

    private var footer: some View {
        HStack {
            if model.isCustomActive {
                Button("Revert to default", role: .destructive) { model.revert() }
            }
            Spacer()
            Button("Close") { dismiss() }
            Button("Apply to my companion") { model.apply(); dismiss() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.resultImage == nil)
        }
        .padding(14)
    }

    // MARK: bits

    private func thumbnail(_ image: CGImage?, side: CGFloat, crisp: Bool) -> some View {
        Group {
            if let image {
                let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                Image(nsImage: ns)
                    .interpolation(crisp ? .none : .high)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: side, height: side)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
    }
}

// MARK: - Model

@MainActor
final class PortraitModel: ObservableObject {
    @Published var sourceImage: CGImage?
    @Published var resultImage: CGImage?
    @Published var resultPalette: CoatPalette?
    @Published var species = Settings.shared.species
    @Published var detected: String?
    @Published var provider = Settings.shared.imageProvider
    @Published var apiKey = ""
    @Published var status = ""
    @Published var busy = false
    @Published var errorText: String?
    @Published var isCustomActive = Settings.shared.customPetEnabled

    private let lib = SpriteLibrary.shared

    init() { apiKey = Keychain.get(account: provider) ?? "" }

    func reloadKey() { apiKey = Keychain.get(account: provider) ?? "" }

    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let img = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        let capped = PixelOps.fit(img, maxSide: 1024)
        sourceImage = capped
        detected = nil
        errorText = nil
        Task {
            let guess = await PetVision.detectSpecies(in: capped)
            if let guess { self.detected = guess; self.species = guess }
        }
    }

    func generate() {
        guard let source = sourceImage else { return }
        errorText = nil
        busy = true
        status = "Rendering…"

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(key.isEmpty ? nil : key, account: provider)
        Settings.shared.imageProvider = provider

        let usingKey = !key.isEmpty
        let engine: PetImageProvider
        let crisp: Bool
        if !usingKey {
            engine = LocalImageProvider(); crisp = false          // free, on-device
        } else if provider == "openai" {
            engine = OpenAIImageProvider(apiKey: key); crisp = true
        } else {
            engine = GeminiImageProvider(apiKey: key); crisp = true
        }

        guard let template = lib.idleTemplate(species: species) else {
            busy = false; status = ""; errorText = "Couldn't load the pose template."
            return
        }
        let sp = species
        let fw = lib.frameWidth, fh = lib.frameHeight, gr = lib.groundRow

        Task {
            do {
                let result = try await PortraitPipeline.run(
                    photo: source, provider: engine, species: sp, template: template,
                    frameWidth: fw, frameHeight: fh, groundRow: gr, crisp: crisp)
                self.resultImage = result.idle
                self.resultPalette = result.palette
                self.status = usingKey ? "Done — preview below." : "Made from your photo — free, on your Mac."
            } catch {
                self.errorText = error.localizedDescription
                self.status = ""
            }
            self.busy = false
        }
    }

    func apply() {
        guard let idle = resultImage, let palette = resultPalette else { return }
        PetPortraitStore.shared.apply(PortraitResult(species: species, idle: idle, palette: palette))
        isCustomActive = true
    }

    func revert() {
        PetPortraitStore.shared.revert()
        isCustomActive = false
        status = "Reverted to the default look."
    }
}
