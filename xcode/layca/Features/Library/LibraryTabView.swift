import SwiftUI

struct LibraryTabView: View {
    let sessions: [ChatSession]
    let activeSessionID: UUID?
    let onSelectSession: (ChatSession) -> Void
    let onRenameSession: (ChatSession, String) -> Void
    let onDeleteSession: (ChatSession) -> Void
    let shareTextForSession: (ChatSession) -> String

    @State private var sessionPendingRename: ChatSession?
    @State private var renameDraft = ""
    @State private var sessionPendingDelete: ChatSession?

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                LiquidBackdrop()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        libraryHeader
                        VStack(spacing: 10) {
                            if sessions.isEmpty {
                                Text("No sessions yet")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.55))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            }

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
                                .contextMenu {
                                    Section("Chat Actions") {
                                        Button {
                                            sessionPendingRename = session
                                            renameDraft = session.title
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }

                                        ShareLink(
                                            item: shareTextForSession(session),
                                            subject: Text(session.title),
                                            message: Text("Shared from Layca")
                                        ) {
                                            Label("Share this chat", systemImage: "square.and.arrow.up")
                                        }

                                        Button(role: .destructive) {
                                            sessionPendingDelete = session
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .liquidCard()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .laycaHideNavigationBar()
            .alert("Rename Chat", isPresented: renameAlertBinding, actions: {
                TextField("Chat name", text: $renameDraft)
                Button("Cancel", role: .cancel) {
                    sessionPendingRename = nil
                    renameDraft = ""
                }
                Button("Save") {
                    if let session = sessionPendingRename {
                        onRenameSession(session, renameDraft)
                    }
                    sessionPendingRename = nil
                    renameDraft = ""
                }
            }, message: {
                Text("Enter a new name for this chat.")
            })
            .confirmationDialog(
                "Delete this chat?",
                isPresented: deleteDialogBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Chat", role: .destructive) {
                    if let session = sessionPendingDelete {
                        onDeleteSession(session)
                    }
                    sessionPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    sessionPendingDelete = nil
                }
            } message: {
                if let sessionPendingDelete {
                    Text("This will permanently remove \"\(sessionPendingDelete.title)\" and its recording.")
                } else {
                    Text("This will permanently remove this chat and its recording.")
                }
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingRename = nil
                    renameDraft = ""
                }
            }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingDelete = nil
                }
            }
        )
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Library")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.9))
            Text("Switch and load saved chat sessions")
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backgroundGradient: some View {
        let colors: [Color]
#if os(macOS)
        colors = [
            Color(red: 0.91, green: 0.94, blue: 0.98),
            Color(red: 0.95, green: 0.96, blue: 0.99),
            Color(red: 0.90, green: 0.94, blue: 0.96)
        ]
#else
        colors = [
            Color(red: 0.88, green: 0.95, blue: 1.0),
            Color(red: 0.95, green: 0.98, blue: 1.0),
            Color(red: 0.90, green: 0.96, blue: 0.95)
        ]
#endif

        return LinearGradient(
            colors: colors,
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
