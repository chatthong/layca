import SwiftUI

/// Displays an SVG avatar rendered by SVGKit (supports gradients).
struct SVGAvatarView: View {

    let name: String
    let size: CGFloat

    init(name: String, size: CGFloat = 34) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if let image = SVGAvatarCache.shared.image(named: name) {
            platformImage(image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: size, height: size)
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
#if canImport(UIKit)
        Image(uiImage: image)
#else
        Image(nsImage: image)
#endif
    }
}
