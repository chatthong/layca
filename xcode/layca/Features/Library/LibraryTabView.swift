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
                backgroundFill

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        libraryHeader
                        VStack(spacing: 10) {
                            if sessions.isEmpty {
                                Text("No sessions yet")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.primary)
            Text("Switch and load saved chat sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var backgroundFill: some View {
#if os(macOS)
        LinearGradient(
            colors: [
                Color(red: 0.91, green: 0.94, blue: 0.98),
                Color(red: 0.95, green: 0.96, blue: 0.99),
                Color(red: 0.90, green: 0.94, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
#else
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
#endif
    }
}

private struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : inactiveIconBackgroundColor)
                Image(systemName: isActive ? "checkmark.bubble.fill" : "bubble.left.and.bubble.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .secondary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(session.rows.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(.thinMaterial)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? .regularMaterial : .thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 0.8)
        )
    }

    private var inactiveIconBackgroundColor: Color {
#if os(macOS)
        Color.white.opacity(0.55)
#else
        Color(uiColor: .secondarySystemBackground)
#endif
    }
}
