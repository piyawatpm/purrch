import SwiftUI

/// The About window — a warm little note about what he's for, with a live view of
/// the cat and an editable name. No photos, nothing personal; just a companion.
struct AboutView: View {
    private let settings = Settings.shared
    @State private var name: String = Settings.shared.name

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                        Color(red: 0.13, green: 0.12, blue: 0.17)],
                               startPoint: .top, endPoint: .bottom)
                CatPreview()
                    .frame(width: 200, height: 150)
            }
            .frame(height: 190)

            VStack(alignment: .leading, spacing: 14) {
                Text(name.isEmpty ? "A little companion" : name)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))

                Text("Someone to keep you company on your screen.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("Can't bring your best friend to the office? This little one fits right on your desktop — wandering, napping, chasing a toy mouse, and keeping half an eye on your to-do list, so you're never quite working alone.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.vertical, 2)

                HStack(spacing: 8) {
                    Text("Call him")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onChange(of: name) { _, new in settings.name = new }
                }

                HStack {
                    Text("Purrch \(appVersion)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(22)
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
