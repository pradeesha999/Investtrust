import FirebaseFirestore
import SwiftUI

struct ChatRoomView: View {
    let chatId: String

    @Environment(AuthService.self) private var auth
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    private let chatService = ChatService()
    private let userService = UserService()
    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var listener: ListenerRegistration?
    @State private var sendError: String?
    @State private var showSendError = false
    @State private var loadError: String?
    @State private var showLoadError = false
    @State private var offerComposerLoadError: String?
    @State private var showOfferComposerLoadError = false

    @State private var partnerName: String = "Chat"
    @State private var partnerAvatarURL: URL?
    @State private var pendingInquirySnapshot: OpportunityInquirySnapshot?
    @State private var participantIds: (seekerId: String, investorId: String)?
    @State private var showOfferSheet = false
    @State private var offerOpportunities: [OpportunityListing] = []
    @State private var offerOpportunityId: String = ""
    @State private var offerAmountText = ""
    @State private var offerRateText = ""
    @State private var offerTimelineText = ""
    @State private var offerDescriptionText = ""
    @State private var offerError: String?
    @State private var isSendingOffer = false

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
                if canCurrentUserMakeOffer {
                    Button {
                        Task { await openOfferComposer() }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(auth.accentColor)
                    }
                    .accessibilityLabel("Make offer")
                    .accessibilityHint("Send a negotiated investment offer in this chat.")
                }
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
        .alert("Could not load messages", isPresented: $showLoadError) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
        .alert("Couldn’t load offers", isPresented: $showOfferComposerLoadError) {
            Button("OK") { offerComposerLoadError = nil }
        } message: {
            Text(offerComposerLoadError ?? "")
        }
        .sheet(isPresented: $showOfferSheet) {
            offerComposerSheet
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
        await MainActor.run {
            participantIds = pair
        }
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
                            : Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    )
                    .overlay {
                        if !isMine {
                            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                                .stroke(Color(.separator).opacity(0.45), lineWidth: 1)
                        }
                    }
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
            case .investmentRequest(let snapshot):
                investmentRequestBubble(snapshot: snapshot, isMine: isMine, createdAt: message.createdAt)
            case .investmentOffer(let snapshot):
                investmentOfferBubble(snapshot: snapshot, isMine: isMine, createdAt: message.createdAt)
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func inquiryBubble(snapshot: OpportunityInquirySnapshot, isMine: Bool, createdAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "briefcase.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(auth.accentColor)
                    .frame(width: 22, height: 22)
                    .background(auth.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Opportunity inquiry")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(auth.accentColor)
                Spacer(minLength: 0)
            }

            Text(snapshot.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                inquiryMetric(label: "Type", value: snapshot.investmentTypeLabel)
                inquiryMetric(label: "Funding", value: snapshot.fundingGoalText)
                inquiryMetric(label: "Min ticket", value: snapshot.minTicketText)
                inquiryMetric(label: "Timeline", value: snapshot.timelineText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Terms")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(snapshot.termsSummary)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
            isMine ? auth.accentColor.opacity(0.12) : Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(isMine ? auth.accentColor.opacity(0.25) : Color(.separator).opacity(0.45), lineWidth: 1)
        }
        .overlay(alignment: isMine ? .bottomTrailing : .bottomLeading) {
            if let createdAt {
                Text(shortTime(createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .offset(y: 18)
            }
        }
    }

    private func inquiryMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func investmentRequestBubble(snapshot: InvestmentRequestSnapshot, isMine: Bool, createdAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(auth.accentColor)
                    .frame(width: 22, height: 22)
                    .background(auth.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(snapshot.requestKindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(auth.accentColor)
                Spacer(minLength: 0)
            }

            Text(snapshot.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                inquiryMetric(label: "Amount", value: snapshot.amountText)
                inquiryMetric(label: "Rate", value: snapshot.interestRateText)
                inquiryMetric(label: "Timeline", value: snapshot.timelineText)
                inquiryMetric(label: "Kind", value: snapshot.requestKindLabel)
            }

            if !snapshot.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.note)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .background(
            isMine ? auth.accentColor.opacity(0.12) : Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(isMine ? auth.accentColor.opacity(0.25) : Color(.separator).opacity(0.45), lineWidth: 1)
        }
        .overlay(alignment: isMine ? .bottomTrailing : .bottomLeading) {
            if let createdAt {
                Text(shortTime(createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .offset(y: 18)
            }
        }
    }

    @ViewBuilder
    private func investmentOfferBubble(snapshot: InvestmentOfferSnapshot, isMine: Bool, createdAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Investment offer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
            }

            Text(snapshot.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                inquiryMetric(label: "Amount", value: snapshot.amountText)
                inquiryMetric(label: "Rate", value: snapshot.interestRateText)
                inquiryMetric(label: "Timeline", value: snapshot.timelineText)
                inquiryMetric(label: "Mode", value: snapshot.isFixedAmount ? "Fixed split" : "Negotiable")
            }

            if !snapshot.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.description)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .background(
            isMine ? Color.orange.opacity(0.14) : Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(isMine ? Color.orange.opacity(0.35) : Color(.separator).opacity(0.45), lineWidth: 1)
        }
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
                if let error {
                    Task { @MainActor in
                        loadError = (error as NSError).localizedDescription
                        showLoadError = true
                    }
                    return
                }
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
                    } else if type == "investment_request",
                              let opportunityId = data["opportunityId"] as? String,
                              let title = data["opportunityTitle"] as? String {
                        let snapshot = InvestmentRequestSnapshot(
                            investmentId: data["investmentId"] as? String,
                            opportunityId: opportunityId,
                            title: title,
                            amountText: data["amountText"] as? String ?? "—",
                            interestRateText: data["interestRateText"] as? String ?? "—",
                            timelineText: data["timelineText"] as? String ?? "—",
                            note: data["note"] as? String ?? "",
                            requestKindLabel: data["requestKindLabel"] as? String ?? "Investment request"
                        )
                        kind = .investmentRequest(snapshot: snapshot)
                    } else if type == "investment_offer",
                              let opportunityId = data["opportunityId"] as? String,
                              let title = data["opportunityTitle"] as? String {
                        let snapshot = InvestmentOfferSnapshot(
                            investmentId: data["investmentId"] as? String,
                            opportunityId: opportunityId,
                            title: title,
                            amountText: data["amountText"] as? String ?? "—",
                            interestRateText: data["interestRateText"] as? String ?? "—",
                            timelineText: data["timelineText"] as? String ?? "—",
                            description: data["descriptionText"] as? String ?? "",
                            isFixedAmount: data["isFixedAmount"] as? Bool ?? false
                        )
                        kind = .investmentOffer(snapshot: snapshot)
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

    private var canCurrentUserMakeOffer: Bool {
        guard let uid = auth.currentUserID, let pair = participantIds else { return false }
        return uid == pair.investorId
    }

    @ViewBuilder
    private var offerComposerSheet: some View {
        NavigationStack {
            InvestmentOfferComposerForm(
                opportunities: offerOpportunities,
                selectedOpportunityId: $offerOpportunityId,
                showOpportunityPicker: offerOpportunities.count > 1,
                emptyListingMessage: "No listings from this seeker are still open for offers. They may already be full, or not marked open.",
                amountText: $offerAmountText,
                rateText: $offerRateText,
                timelineText: $offerTimelineText,
                descriptionText: $offerDescriptionText,
                errorText: offerError
            )
            .navigationTitle("Make offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showOfferSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSendingOffer {
                        ProgressView()
                    } else {
                        Button("Send offer") {
                            Task { await submitOffer() }
                        }
                        .disabled(offerOpportunities.isEmpty)
                    }
                }
            }
        }
    }

    private var selectedOfferOpportunity: OpportunityListing? {
        if !offerOpportunityId.isEmpty, let match = offerOpportunities.first(where: { $0.id == offerOpportunityId }) {
            return match
        }
        return offerOpportunities.first
    }

    private func openOfferComposer() async {
        guard auth.currentUserID != nil else { return }
        if let fresh = try? await chatService.fetchParticipantIds(chatId: chatId) {
            await MainActor.run { participantIds = fresh }
        }
        guard canCurrentUserMakeOffer, let pair = participantIds else { return }
        do {
            let openRows = try await opportunityService.fetchSeekerListingsEligibleForOffers(
                ownerId: pair.seekerId,
                limit: 100,
                refineByInvestorCapacity: false
            )
            await MainActor.run {
                offerOpportunities = openRows
                offerOpportunityId = openRows.first?.id ?? ""
                if let first = openRows.first {
                    let cap = max(1, first.maximumInvestors ?? 1)
                    offerAmountText = cap > 1 ? "" : String(format: "%.0f", first.amountRequested)
                    offerRateText = first.interestRate > 0 ? String(format: "%.2f", first.interestRate) : ""
                    offerTimelineText = "\(max(1, first.repaymentTimelineMonths))"
                } else {
                    offerAmountText = ""
                    offerRateText = ""
                    offerTimelineText = ""
                }
                offerDescriptionText = ""
                offerError = nil
                showOfferSheet = true
            }
        } catch {
            await MainActor.run {
                offerComposerLoadError = (error as NSError).localizedDescription
                showOfferComposerLoadError = true
            }
        }
    }

    private func submitOffer() async {
        guard let uid = auth.currentUserID,
              let selected = selectedOfferOpportunity else { return }
        let cap = max(1, selected.maximumInvestors ?? 1)
        let multi = cap > 1
        let amountValue: Double?
        if multi {
            amountValue = InvestmentOfferComposerForm.offerAmountForOpportunity(selected)
        } else {
            let cleaned = offerAmountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
            amountValue = Double(cleaned)
        }
        let rateValue = Double(offerRateText.trimmingCharacters(in: .whitespacesAndNewlines))
        let timelineDigits = offerTimelineText.filter(\.isNumber)
        let timelineValue = Int(timelineDigits)
        guard let amountValue, amountValue > 0,
              let rateValue, rateValue > 0,
              let timelineValue, timelineValue > 0 else {
            await MainActor.run {
                offerError = "Enter valid offer terms to continue."
            }
            return
        }

        isSendingOffer = true
        defer { isSendingOffer = false }
        do {
            let row = try await investmentService.createOrUpdateOfferRequest(
                opportunity: selected,
                investorId: uid,
                proposedAmount: amountValue,
                proposedInterestRate: rateValue,
                proposedTimelineMonths: timelineValue,
                description: offerDescriptionText,
                source: .chat,
                chatId: chatId
            )
            let snapshot = InvestmentOfferSnapshot(
                investmentId: row.id,
                opportunityId: selected.id,
                title: selected.title,
                amountText: InvestmentOfferComposerForm.lkr(row.offeredAmount ?? row.investmentAmount),
                interestRateText: String(format: "%.2f%%", row.offeredInterestRate ?? row.finalInterestRate ?? rateValue),
                timelineText: "\((row.offeredTimelineMonths ?? row.finalTimelineMonths ?? timelineValue)) months",
                description: offerDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                isFixedAmount: multi
            )
            _ = try await chatService.sendInvestmentOfferCard(chatId: chatId, senderId: uid, snapshot: snapshot)
            await MainActor.run {
                showOfferSheet = false
                offerDescriptionText = ""
                offerError = nil
            }
        } catch {
            await MainActor.run {
                offerError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
            }
        }
    }

}

#Preview {
    NavigationStack {
        ChatRoomView(chatId: "preview")
            .environment(AuthService.previewSignedIn)
    }
}
