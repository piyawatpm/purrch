import SwiftUI

/// A grid of every animation, each a button that plays it on the live cat. The
/// easy way to see the whole set.
struct AnimationTesterView: View {
    let play: (String) -> Void
    private let names = SpriteLibrary.shared.animationNames

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Animations").font(.system(size: 15, weight: .semibold))
                Text("\(names.count) in all — click one to play it on him.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(names, id: \.self) { name in
                        Button { play(name) } label: {
                            Text(name.capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.06)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 460)
    }
}
