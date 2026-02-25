import SwiftUI

/// Displays a pre-rendered SVG avatar from SVGAvatarCache.
/// Shows a grey placeholder circle while the async render completes.
struct SVGAvatarView: View {

    let name: String
    let size: CGFloat

    @ObservedObject private var cache: SVGAvatarCache = .shared

    init(name: String, size: CGFloat = 34) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if let image = cache.image(named: name) {
#if canImport(UIKit)
                Image(uiImage: image)
#else
                Image(nsImage: image)
#endif
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
}
