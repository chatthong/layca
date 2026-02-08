import SwiftUI

struct ChatTabView: View {
    @Binding var isRecording: Bool

    let modelProgress: Double
    let activeSessionTitle: String
    let activeSessionDateText: String
    let liveChatItems: [TranscriptRow]
    let onExportTap: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                LiquidBackdrop()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        recorderCard
                        liveSegmentsCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                topToolbar
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.95, blue: 1.0),
                Color(red: 0.95, green: 0.98, blue: 1.0),
                Color(red: 0.90, green: 0.96, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topToolbar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text(activeSessionTitle)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassCapsuleStyle()

            Spacer()

            Button(action: onExportTap) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.55), lineWidth: 0.9)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
        }
    }

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                waveformPanel

                VStack(alignment: .leading, spacing: 10) {
                    Text("New Recording")
                        .font(.headline)
                        .foregroundStyle(.black.opacity(0.72))

                    Text(isRecording ? "00:12:31" : "00:00:00")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.85))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    recorderActionControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Large v3 Turbo")
                Spacer()
                Text("\(Int(modelProgress * 100))% ready")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.black.opacity(0.50))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 12)
    }

    private var waveformPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.12, blue: 0.22).opacity(0.65),
                            Color.black.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(alignment: .center, spacing: 3) {
                ForEach([8, 14, 24, 34, 26, 16, 12, 18, 10], id: \.self) { barHeight in
                    Capsule(style: .continuous)
                        .fill(Color.red.opacity(0.78))
                        .frame(width: 2.4, height: CGFloat(barHeight))
                }
            }

            Rectangle()
                .fill(isRecording ? Color.red : Color.blue)
                .frame(width: 2)
                .overlay(
                    VStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 8, height: 8)
                        Spacer()
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 8)
                )
        }
        .frame(width: 120, height: 126)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.7)
        )
    }

    private var recorderActionControl: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isRecording.toggle()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isRecording ? "pause.fill" : "record.circle.fill")
                    .font(.headline.weight(.semibold))
                Text(isRecording ? "Pause" : "Record")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isRecording ? Color.red.opacity(0.96) : .black.opacity(0.80))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isRecording
                                ? [Color.red.opacity(0.18), Color.white.opacity(0.20)]
                                : [Color.white.opacity(0.52), Color.white.opacity(0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.48), lineWidth: 0.9)
            )
        }
        .buttonStyle(.plain)
    }

    private var liveSegmentsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Latest Transcript")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.75))
                Spacer()
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.55))
            }

            ForEach(liveChatItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    avatarView(for: item)
                    messageBubble(for: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .liquidCard()
    }

    private func avatarView(for item: TranscriptRow) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: item.avatarPalette,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: item.avatarSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: 34, height: 34)
        .overlay(
            Circle()
                .stroke(.white.opacity(0.6), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 7, x: 0, y: 4)
    }

    private func messageBubble(for item: TranscriptRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                speakerMeta(for: item)
                Spacer(minLength: 8)
                timestampView(for: item)
            }

            Text(item.text)
                .font(.body)
                .foregroundStyle(.black.opacity(0.82))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.50))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.8)
        )
    }

    private func speakerMeta(for item: TranscriptRow) -> some View {
        HStack(spacing: 6) {
            Text(item.speaker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black.opacity(0.60))

            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .font(.caption2.weight(.bold))
                Text(item.language)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.black.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.52))
            )
        }
    }

    private func timestampView(for item: TranscriptRow) -> some View {
        Text(item.time)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black.opacity(0.43))
    }
}
