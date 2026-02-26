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
        if let image = SVGAvatarCache.shared.image(named: name) {
            platformImage(image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: size, height: size)
        }
    }

    // Returns a concrete Image type so .resizable() resolves correctly.
    // #if inside @ViewBuilder makes the result opaque (some View), losing Image modifiers.
    private func platformImage(_ image: PlatformImage) -> Image {
#if canImport(UIKit)
        Image(uiImage: image)
#else
        Image(nsImage: image)
#endif
    }
}
