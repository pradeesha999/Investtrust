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
                        message: "Negotiation and investment chats will appear here when you contact a seeker or investor."
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
                ChatRoomView(chatId: link.chatId)
            }
            .task(id: auth.currentUserID) {
                await loadThreads()
            }
            .refreshable {
                await loadThreads()
            }
            .onChange(of: tabRouter.pendingChatDeepLink) { _, link in
                guard let link else { return }
                path.append(link)
                tabRouter.pendingChatDeepLink = nil
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
}

#Preview {
    ChatListView()
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
}
