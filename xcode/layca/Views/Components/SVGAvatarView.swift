import SwiftUI

/// Displays a pre-rendered SVG avatar from SVGAvatarCache.
/// Shows a grey placeholder circle while the async render completes.
struct SVGAvatarView: View {

    let name: String
    let size: CGFloat

    init(name: String, size: CGFloat = 34) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if let image = SVGAvatarCache.shared.image(named: name) {
                // platformImage() returns concrete Image so .resizable() resolves.
                // Putting #if canImport inside a @ViewBuilder makes the branch type
                // opaque (some View), which loses .resizable() — helper avoids that.
                platformImage(image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Placeholder while SVG is being rendered — plain grey circle.
                Circle()
                    .fill(Color(.systemGray4))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Helpers

    private func platformImage(_ image: PlatformImage) -> Image {
#if canImport(UIKit)
        Image(uiImage: image)
#else
        Image(nsImage: image)
#endif
    }
}
