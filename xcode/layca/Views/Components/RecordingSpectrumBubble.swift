import SwiftUI

struct RecordingSpectrumBubble: View {
    let waveformBars: [Double]
    var cornerRadius: CGFloat = 16
    var horizontalPadding: CGFloat = 13
    var verticalPadding: CGFloat = 11
    var strokeOpacity: Double = 0.12

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing listening indicator dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 0.85)
                .opacity(isPulsing ? 1.0 : 0.55)

            // Waveform bars
            HStack(alignment: .center, spacing: 3) {
                ForEach(displayLevels.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.94),
                                    Color.accentColor.opacity(0.72)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3, height: barHeight(for: displayLevels[index]))
                }
            }
            .frame(height: 32, alignment: .center)

            // Listening label
            Text("Listening...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .opacity(isPulsing ? 0.88 : 0.44)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.primary.opacity(strokeOpacity), lineWidth: 0.8)
                )
        )
        .animation(.interpolatingSpring(stiffness: 280, damping: 18), value: waveformBars)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private var displayLevels: [Double] {
        let targetCount = 16
        let source = waveformBars.isEmpty
            ? Array(repeating: 0.08, count: targetCount)
            : Array(waveformBars.prefix(targetCount))
        guard source.count < targetCount else {
            return source
        }
        return source + Array(repeating: source.last ?? 0.08, count: targetCount - source.count)
    }

    private func barHeight(for level: Double) -> CGFloat {
        let normalized = min(max(level, 0.04), 1)
        return max(CGFloat(normalized) * 28, 4)
    }
}
