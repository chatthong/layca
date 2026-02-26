import SwiftUI
import WebKit
import Observation

// MARK: - Platform image alias

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - SVGAvatarCache

/// Pre-renders all 24 avatar SVGs via WKWebView at app launch so SwiftUI
/// can read them synchronously from the cache later.
///
/// Uses @Observable (Swift/iOS 17+) rather than ObservableObject because
/// @MainActor-isolated classes fail the ObservableObject conformance check
/// in Swift 6 strict concurrency mode.
@Observable
final class SVGAvatarCache {

    static let shared = SVGAvatarCache()

    /// Keyed by asset name, e.g. "avatar_1". @Observable tracks accesses
    /// automatically — no @Published needed.
    var images: [String: PlatformImage] = [:]

    private init() {}

    /// Kick off background pre-render of all 24 avatars.
    /// Safe to call multiple times; second call is a no-op once loading starts.
    func preloadAll() {
        guard images.isEmpty else { return }
        Task { @MainActor in
            await withTaskGroup(of: (String, PlatformImage?).self) { group in
                for i in 1...24 {
                    let name = "avatar_\(i)"
                    group.addTask { @MainActor in
                        let img = await SVGWebRenderer.render(named: name, size: CGSize(width: 72, height: 72))
                        return (name, img)
                    }
                }
                for await (name, img) in group {
                    if let img { images[name] = img }
                }
            }
        }
    }

    func image(named name: String) -> PlatformImage? {
        images[name]
    }
}

// MARK: - SVGWebRenderer

/// Loads one SVG data asset, renders it in an off-screen WKWebView, and
/// returns the snapshot image. The renderer retains itself via a static set
/// until the WKNavigationDelegate callback fires.
@MainActor
private final class SVGWebRenderer: NSObject, WKNavigationDelegate {

    private static var active: Set<SVGWebRenderer> = []

    private let webView: WKWebView
    private var continuation: CheckedContinuation<PlatformImage?, Never>?

    // MARK: Public entry point

    static func render(named name: String, size: CGSize) async -> PlatformImage? {
        guard let asset = NSDataAsset(name: name),
              let svgText = String(data: asset.data, encoding: .utf8) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let renderer = SVGWebRenderer(svgText: svgText, size: size, continuation: continuation)
            active.insert(renderer)
        }
    }

    // MARK: Init

    private init(
        svgText: String,
        size: CGSize,
        continuation: CheckedContinuation<PlatformImage?, Never>
    ) {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        self.continuation = continuation
        super.init()

        webView.navigationDelegate = self
#if canImport(UIKit)
        webView.isOpaque = false
#endif

        let w = Int(size.width)
        let h = Int(size.height)
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=\(w), initial-scale=1">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: \(w)px; height: \(h)px; overflow: hidden; background: transparent; }
        svg { width: \(w)px; height: \(h)px; display: block; }
        </style>
        </head>
        <body>\(svgText)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self else { return }
            self.continuation?.resume(returning: image)
            self.continuation = nil
            SVGWebRenderer.active.remove(self)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
        SVGWebRenderer.active.remove(self)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(returning: nil)
        continuation = nil
        SVGWebRenderer.active.remove(self)
    }
}
