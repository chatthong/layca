import SwiftUI

struct LiquidBackdrop: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(laycaDesktopOptimized ? 0.18 : 0.35))
                .frame(
                    width: laycaDesktopOptimized ? 340 : 260,
                    height: laycaDesktopOptimized ? 340 : 260
                )
                .blur(radius: laycaDesktopOptimized ? 54 : 36)
                .offset(x: -110, y: -250)

            Circle()
                .fill(Color.blue.opacity(laycaDesktopOptimized ? 0.16 : 0.25))
                .frame(
                    width: laycaDesktopOptimized ? 280 : 220,
                    height: laycaDesktopOptimized ? 280 : 220
                )
                .blur(radius: laycaDesktopOptimized ? 56 : 40)
                .offset(x: 130, y: -160)

            Circle()
                .fill(Color.mint.opacity(laycaDesktopOptimized ? 0.16 : 0.28))
                .frame(
                    width: laycaDesktopOptimized ? 360 : 280,
                    height: laycaDesktopOptimized ? 360 : 280
                )
                .blur(radius: laycaDesktopOptimized ? 68 : 55)
                .offset(x: 120, y: 380)
        }
    }

    private var laycaDesktopOptimized: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }
}
