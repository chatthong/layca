import SwiftUI

struct LibraryTabView: View {
    let sessions: [ChatSession]
    let activeSessionID: UUID?
    let onSelectSession: (ChatSession) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                LiquidBackdrop()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Library")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.9))
                        Text("Switch and load saved chat sessions")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.6))
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(sessions) { session in
                                Button {
                                    onSelectSession(session)
                                } label: {
                                    SessionRow(
                                        session: session,
                                        isActive: session.id == activeSessionID
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(18)
                .liquidCard()
                .padding(.horizontal, 18)
            }
            .navigationBarHidden(true)
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
}

private struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.cyan.opacity(0.95) : Color.white.opacity(0.66))
                Image(systemName: isActive ? "checkmark.bubble.fill" : "bubble.left.and.bubble.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .black.opacity(0.62))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.82))
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.58))
            }

            Spacer()

            Text("\(session.rows.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.58))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? .white.opacity(0.68) : .white.opacity(0.50))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.60), lineWidth: 0.8)
        )
    }
}
