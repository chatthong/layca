#if os(iOS)
import SwiftUI

enum IOSWorkspaceSection: String, CaseIterable, Identifiable {
    case chat
    case setting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "Layca Chat"
        case .setting:
            return "Setting"
        }
    }

    var symbol: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .setting:
            return "slider.horizontal.3"
        }
    }
}

struct IOSWorkspaceSidebarView: View {
    @Binding var selectedSection: IOSWorkspaceSection
    let sessions: [ChatSession]
    let activeSessionID: UUID?
    let onSelectSession: (ChatSession) -> Void
    let onRenameSession: (ChatSession, String) -> Void
    let onDeleteSession: (ChatSession) -> Void
    let shareTextForSession: (ChatSession) -> String
    let onSelectChatWorkspace: () -> Void
    let onCreateSession: () -> Void

    @State private var sessionPendingRename: ChatSession?
    @State private var renameDraft = ""
    @State private var sessionPendingDelete: ChatSession?

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                sidebarBackground
                    .ignoresSafeArea(edges: .vertical)

                VStack(spacing: 0) {
                    topActions
                        .padding(.top, 4)
                        .padding(.bottom, 18)
                        .padding(.horizontal, 18)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 26) {
                            workspaceSection
                            recentChatsSection
                        }
                        .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
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
        .simultaneousGesture(
            TapGesture().onEnded {
                NotificationCenter.default.post(
                    name: Notification.Name("LaycaCancelTitleRenameEditing"),
                    object: nil
                )
            }
        )
    }

    private var sidebarBackground: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear,
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var topActions: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Text("Search")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 0.8)
                    )
            )

            Button(action: onCreateSession) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.14), lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Chat")
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workspace")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.horizontal, 4)

            workspaceRow(for: .chat)
            workspaceRow(for: .setting)
        }
    }

    private func workspaceRow(for section: IOSWorkspaceSection) -> some View {
        Button {
            if section == .chat {
                onSelectChatWorkspace()
            } else {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 28, alignment: .center)
                Text(section.title)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isWorkspaceSectionSelected(section)
                            ? AnyShapeStyle(Color.white.opacity(0.20))
                            : AnyShapeStyle(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isWorkspaceSectionSelected(section) ? .white.opacity(0.16) : .clear, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var recentChatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Chats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.horizontal, 4)

            LazyVStack(alignment: .leading, spacing: 6) {
                if sessions.isEmpty {
                    Text("No chats yet")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                } else {
                    ForEach(0..<sessions.count, id: \.self) { index in
                        let session = sessions[index]
                        recentChatRow(for: session)
                    }
                }
            }
        }
    }

    private func recentChatRow(for session: ChatSession) -> some View {
        Button {
            selectedSection = .chat
            onSelectSession(session)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 17, weight: activeSessionID == session.id ? .semibold : .regular))
                    .lineLimit(1)
                Text(session.formattedDate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        activeSessionID == session.id
                            ? AnyShapeStyle(Color.white.opacity(0.22))
                            : AnyShapeStyle(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(activeSessionID == session.id ? .white.opacity(0.14) : .clear, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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

    private func isWorkspaceSectionSelected(_ section: IOSWorkspaceSection) -> Bool {
        switch section {
        case .chat:
            return selectedSection == .chat && activeSessionID == nil
        case .setting:
            return selectedSection == .setting
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
}
#endif
