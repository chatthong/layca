import SVGKit

// MARK: - Platform image alias

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - SVGAvatarCache

/// Lazy cache for SVG avatars rendered by SVGKit.
/// SVGKit renders synchronously including linearGradient / radialGradient.
final class SVGAvatarCache {

    static let shared = SVGAvatarCache()
    private var cache: [String: PlatformImage] = [:]
    private init() {}

    func image(named name: String) -> PlatformImage? {
        if let hit = cache[name] { return hit }
        guard let asset = NSDataAsset(name: name) else { return nil }
        guard let svg = SVGKImage(data: asset.data) else { return nil }
        svg.size = CGSize(width: 72, height: 72)
#if canImport(UIKit)
        let img = svg.uiImage
#else
        let img = svg.nsImage
#endif
        cache[name] = img
        return img
    }
}
