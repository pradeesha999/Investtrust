import SwiftUI

struct ChatListView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter

    private let chatService = ChatService()

    @State private var threads: [ChatThread] = []
    @State private var loadError: String?
    @State private var showLoadError = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if threads.isEmpty {
                    StatusBlock(
                        icon: "bubble.left.and.bubble.right",
                        title: "No conversations yet",
                        message: auth.activeProfile == .investor
                            ? "Start from any opportunity detail to message a seeker."
                            : "Investor conversations will appear here when requests begin."
                    )
                    .padding(AppTheme.screenPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(threads) { thread in
                        NavigationLink(value: ChatDeepLink(chatId: thread.id)) {
                            ChatThreadRowView(thread: thread, currentUserId: auth.currentUserID)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chat")
            .navigationDestination(for: ChatDeepLink.self) { link in
                ChatRoomView(chatId: link.chatId, pendingInquirySnapshot: link.inquirySnapshot)
            }
            .task(id: auth.currentUserID) {
                await loadThreads()
                consumePendingDeepLinkIfNeeded()
            }
            .refreshable {
                await loadThreads()
            }
            .onAppear {
                consumePendingDeepLinkIfNeeded()
            }
            .onChange(of: tabRouter.pendingChatDeepLink) { _, link in
                guard let _ = link else { return }
                consumePendingDeepLinkIfNeeded()
            }
            .alert("Could not load chats", isPresented: $showLoadError) {
                Button("OK") { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
        }
    }

    private func loadThreads() async {
        guard let uid = auth.currentUserID else {
            threads = []
            return
        }
        do {
            threads = try await chatService.fetchThreads(for: uid)
        } catch {
            loadError = error.localizedDescription
            showLoadError = true
        }
    }

    private func consumePendingDeepLinkIfNeeded() {
        guard let link = tabRouter.pendingChatDeepLink else { return }
        path = NavigationPath()
        path.append(link)
        tabRouter.pendingChatDeepLink = nil
    }
}

#Preview {
    ChatListView()
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
}
