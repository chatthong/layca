import SwiftUI

extension View {
    func liquidCard() -> some View {
#if os(macOS)
        self
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.36), lineWidth: 0.7)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 6)
#else
        self
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.26), .white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 14)
#endif
    }

    func glassCapsuleStyle() -> some View {
#if os(macOS)
        self
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.36), lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
#else
        self
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
#endif
    }
}
