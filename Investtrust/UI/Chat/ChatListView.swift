import SwiftUI

struct ChatListView: View {
    @Environment(AuthService.self) private var auth
    private let chatService = ChatService()

    @State private var threads: [ChatThread] = []
    @State private var loadError: String?
    @State private var showLoadError = false

    var body: some View {
        NavigationStack {
            Group {
                if threads.isEmpty {
                    VStack(spacing: 12) {
                        Text("Negotiation and investment chats will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                Text("No chats yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            )
                            .frame(height: 120)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(threads) { thread in
                        NavigationLink {
                            ChatRoomView(chatId: thread.id, title: thread.title)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thread.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if !thread.lastMessagePreview.isEmpty {
                                    Text(thread.lastMessagePreview)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chat")
            .task(id: auth.currentUserID) {
                await loadThreads()
            }
            .refreshable {
                await loadThreads()
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
}
