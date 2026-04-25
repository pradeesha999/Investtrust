import FirebaseFirestore
import SwiftUI

struct ChatRoomView: View {
    let chatId: String

    @Environment(AuthService.self) private var auth
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    private let chatService = ChatService()
    private let userService = UserService()

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var listener: ListenerRegistration?
    @State private var sendError: String?
    @State private var showSendError = false

    @State private var partnerName: String = "Chat"
    @State private var partnerAvatarURL: URL?
    @State private var pendingInquirySnapshot: OpportunityInquirySnapshot?

    init(chatId: String, pendingInquirySnapshot: OpportunityInquirySnapshot? = nil) {
        self.chatId = chatId
        _pendingInquirySnapshot = State(initialValue: pendingInquirySnapshot)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty {
                            Text("Say hello to start the conversation.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 24)
                        }
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
                        if reduceMotion {
                            proxy.scrollTo(last, anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .accessibilityLabel("Message text")

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, auth.accentColor)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
                .accessibilityHint("Sends your message to the chat.")
            }
            .padding(12)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    partnerAvatar
                        .frame(width: 34, height: 34)
                    Text(partnerName)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
        }
        .task(id: chatId) {
            await loadPartnerHeader()
        }
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

    @ViewBuilder
    private var partnerAvatar: some View {
        if let partnerAvatarURL {
            AsyncImage(url: partnerAvatarURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
            .clipShape(Circle())
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(AppTheme.secondaryFill)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    private func loadPartnerHeader() async {
        guard let uid = auth.currentUserID else { return }
        guard let pair = try? await chatService.fetchParticipantIds(chatId: chatId) else { return }
        let otherId = pair.seekerId == uid ? pair.investorId : pair.seekerId
        guard let profile = try? await userService.fetchProfile(userID: otherId) else {
            await MainActor.run {
                partnerName = "Chat"
                partnerAvatarURL = nil
            }
            return
        }
        await MainActor.run {
            let raw = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            partnerName = raw.isEmpty ? "Member" : raw
            if let s = profile.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               let u = URL(string: s) {
                partnerAvatarURL = u
            } else {
                partnerAvatarURL = nil
            }
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
            switch message.kind {
            case .text:
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isMine
                            ? auth.accentColor.opacity(0.2)
                            : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    )
                    .overlay(alignment: isMine ? .bottomTrailing : .bottomLeading) {
                        if let createdAt = message.createdAt {
                            Text(shortTime(createdAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .offset(y: 18)
                        }
                    }
            case .opportunityInquiry(let snapshot):
                inquiryBubble(snapshot: snapshot, isMine: isMine, createdAt: message.createdAt)
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func inquiryBubble(snapshot: OpportunityInquirySnapshot, isMine: Bool, createdAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Opportunity inquiry", systemImage: "briefcase.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(auth.accentColor)

            Text(snapshot.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                inquiryLine(label: "Type", value: snapshot.investmentTypeLabel)
                inquiryLine(label: "Funding", value: snapshot.fundingGoalText)
                inquiryLine(label: "Min ticket", value: snapshot.minTicketText)
                inquiryLine(label: "Timeline", value: snapshot.timelineText)
                inquiryLine(label: "Terms", value: snapshot.termsSummary)
            }

            NavigationLink {
                OpportunityDetailView(opportunityId: snapshot.opportunityId)
            } label: {
                Text("View opportunity")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
            .background(auth.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
        }
        .padding(12)
        .background(
            isMine ? auth.accentColor.opacity(0.12) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        )
        .overlay(alignment: isMine ? .bottomTrailing : .bottomLeading) {
            if let createdAt {
                Text(shortTime(createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .offset(y: 18)
            }
        }
    }

    private func inquiryLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                    let type = (data["type"] as? String ?? "text").lowercased()
                    let kind: ChatMessage.Kind
                    if type == "opportunity_inquiry",
                       let opportunityId = data["opportunityId"] as? String,
                       let title = data["opportunityTitle"] as? String {
                        let snapshot = OpportunityInquirySnapshot(
                            opportunityId: opportunityId,
                            title: title,
                            investmentTypeLabel: data["investmentTypeLabel"] as? String ?? "—",
                            fundingGoalText: data["fundingGoalText"] as? String ?? "—",
                            minTicketText: data["minTicketText"] as? String ?? "—",
                            termsSummary: data["termsSummary"] as? String ?? "—",
                            timelineText: data["timelineText"] as? String ?? "—"
                        )
                        kind = .opportunityInquiry(snapshot: snapshot)
                    } else {
                        kind = .text
                    }
                    return ChatMessage(
                        id: doc.documentID,
                        senderId: senderId,
                        text: text,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                        kind: kind
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
            if let snapshot = pendingInquirySnapshot {
                try await chatService.sendOpportunityInquiryAndMessage(
                    chatId: chatId,
                    senderId: uid,
                    snapshot: snapshot,
                    text: text
                )
                await MainActor.run {
                    pendingInquirySnapshot = nil
                }
            } else {
                try await chatService.sendMessage(chatId: chatId, senderId: uid, text: text)
            }
            AppHaptics.lightImpact()
        } catch {
            inputText = text
            presentSendError(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        ChatRoomView(chatId: "preview")
            .environment(AuthService.previewSignedIn)
    }
}
