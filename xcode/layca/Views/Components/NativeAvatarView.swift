import SwiftUI

/// Native SwiftUI orb avatar — radial gradient with two colors + specular
/// highlight. Zero dependencies, renders instantly, supports all platforms.
struct NativeAvatarView: View {

    /// Stable index into the 24 gradient palette derived from speakerID hash.
    let paletteIndex: Int
    let size: CGFloat

    init(paletteIndex: Int, size: CGFloat = 34) {
        self.paletteIndex = abs(paletteIndex) % Self.palette.count
        self.size = size
    }

    // Convenience: hash any string to a stable palette index.
    init(speakerID: String, size: CGFloat = 34) {
        let hash = speakerID.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        self.init(paletteIndex: abs(hash), size: size)
    }

    private var inner: Color { Self.palette[paletteIndex].0 }
    private var outer: Color { Self.palette[paletteIndex].1 }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [inner, outer],
                    center: UnitPoint(x: 0.35, y: 0.28),
                    startRadius: 0,
                    endRadius: size * 0.88
                )
            )
            .overlay(
                // Specular highlight — simulates a 3D light source
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.55), .clear],
                            center: UnitPoint(x: 0.3, y: 0.22),
                            startRadius: 0,
                            endRadius: size * 0.42
                        )
                    )
            )
            .frame(width: size, height: size)
    }

    // MARK: — 24 orb gradient pairs (inner bright → outer deep)

    static let palette: [(Color, Color)] = [
        (Color(hex: "#FFB3B3"), Color(hex: "#B91C1C")), // 01 coral
        (Color(hex: "#FFCB99"), Color(hex: "#C2410C")), // 02 peach
        (Color(hex: "#FFE082"), Color(hex: "#B45309")), // 03 amber
        (Color(hex: "#FFF176"), Color(hex: "#A16207")), // 04 gold
        (Color(hex: "#D9F99D"), Color(hex: "#3F6212")), // 05 lime
        (Color(hex: "#86EFAC"), Color(hex: "#166534")), // 06 green
        (Color(hex: "#6EE7B7"), Color(hex: "#065F46")), // 07 emerald
        (Color(hex: "#5EEAD4"), Color(hex: "#134E4A")), // 08 teal
        (Color(hex: "#7DD3FC"), Color(hex: "#075985")), // 09 sky
        (Color(hex: "#93C5FD"), Color(hex: "#1E40AF")), // 10 blue
        (Color(hex: "#A5B4FC"), Color(hex: "#3730A3")), // 11 indigo
        (Color(hex: "#C4B5FD"), Color(hex: "#5B21B6")), // 12 violet
        (Color(hex: "#D8B4FE"), Color(hex: "#6B21A8")), // 13 purple
        (Color(hex: "#F0ABFC"), Color(hex: "#701A75")), // 14 fuchsia
        (Color(hex: "#F9A8D4"), Color(hex: "#9D174D")), // 15 pink
        (Color(hex: "#FDA4AF"), Color(hex: "#9F1239")), // 16 rose
        (Color(hex: "#FCA5A5"), Color(hex: "#991B1B")), // 17 red
        (Color(hex: "#FDBA74"), Color(hex: "#9A3412")), // 18 orange
        (Color(hex: "#FCD34D"), Color(hex: "#92400E")), // 19 yellow-amber
        (Color(hex: "#A3E635"), Color(hex: "#365314")), // 20 yellow-green
        (Color(hex: "#34D399"), Color(hex: "#064E3B")), // 21 mint
        (Color(hex: "#22D3EE"), Color(hex: "#164E63")), // 22 cyan
        (Color(hex: "#60A5FA"), Color(hex: "#1E3A8A")), // 23 royal blue
        (Color(hex: "#818CF8"), Color(hex: "#312E81")), // 24 deep indigo
    ]
}
