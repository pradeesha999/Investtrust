import FirebaseFirestore
import SwiftUI

struct ChatRoomView: View {
    let chatId: String
    let title: String

    @Environment(AuthService.self) private var auth
    private let chatService = ChatService()

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var listener: ListenerRegistration?
    @State private var sendError: String?
    @State private var showSendError = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AppTheme.accent)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startListening() }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .alert("Could not send", isPresented: $showSendError) {
            Button("OK") { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
    }

    private func presentSendError(_ message: String) {
        sendError = message
        showSendError = true
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        let isMine = message.senderId == auth.currentUserID
        HStack {
            if isMine { Spacer(minLength: 48) }
            Text(message.text)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isMine
                        ? AppTheme.accent.opacity(0.2)
                        : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                )
            if !isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private func startListening() {
        listener?.remove()
        listener = Firestore.firestore()
            .collection("chats").document(chatId).collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let parsed: [ChatMessage] = docs.compactMap { doc in
                    let data = doc.data()
                    guard let senderId = data["senderId"] as? String,
                          let text = data["text"] as? String else { return nil }
                    return ChatMessage(
                        id: doc.documentID,
                        senderId: senderId,
                        text: text,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
                    )
                }
                Task { @MainActor in
                    messages = parsed
                }
            }
    }

    private func send() async {
        guard let uid = auth.currentUserID else { return }
        let text = inputText
        inputText = ""
        do {
            try await chatService.sendMessage(chatId: chatId, senderId: uid, text: text)
        } catch {
            inputText = text
            presentSendError(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        ChatRoomView(chatId: "preview", title: "Samsung phone")
            .environment(AuthService.previewSignedIn)
    }
}
