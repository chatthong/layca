//
//  laycaApp.swift
//  layca
//
//  Created by Chatthong Rimthong on 8/2/26.
//

import SwiftUI

@main
struct laycaApp: App {
    init() {
        // Pre-render all 24 SVG avatars via WKWebView so they're cached
        // before the chat view appears. WKWebView supports full SVG gradient
        // rendering unlike Xcode's built-in imageset SVG rasterizer.
        SVGAvatarCache.shared.preloadAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
