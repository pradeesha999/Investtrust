import SwiftUI

/// Investor-facing detail screen for a market opportunity (layout inspired by `design/invest info.svg`).
/// Always loads the listing by Firestore document ID so navigation never shows the wrong row.
struct OpportunityDetailView: View {
    let opportunityId: String

    @State private var opportunity: OpportunityListing?
    @State private var loadError: String?

    @Environment(AuthService.self) private var auth
    private let chatService = ChatService()
    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()

    @State private var activeChat: ActiveChatDestination?
    @State private var contactError: String?
    @State private var showContactError = false
    @State private var isOpeningChat = false
    @State private var myLatestRequest: InvestmentListing?
    @State private var showInvestSheet = false

    private struct ActiveChatDestination: Identifiable, Hashable {
        let chatId: String
        let title: String
        var id: String { chatId }
    }

    /// Production path: load from Firestore by id (avoids `NavigationLink(value:)` / `Hashable` mismatches in lists).
    init(opportunityId: String) {
        self.opportunityId = opportunityId
    }

    /// Preview / tests: optional seed while network loads.
    init(opportunity: OpportunityListing) {
        opportunityId = opportunity.id
        _opportunity = State(initialValue: opportunity)
    }

    var body: some View {
        Group {
            if let opportunity {
                detailContent(opportunity)
            } else if let loadError {
                StatusBlock(
                    icon: "exclamationmark.triangle.fill",
                    title: "Couldn’t load this listing",
                    message: loadError,
                    iconColor: .orange
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Opportunity")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeChat) { dest in
            ChatRoomView(chatId: dest.chatId, title: dest.title)
        }
        .alert("Could not open chat", isPresented: $showContactError) {
            Button("OK") { contactError = nil }
        } message: {
            Text(contactError ?? "")
        }
        .task(id: opportunityId) {
            await loadOpportunityFromServer()
        }
        .sheet(isPresented: $showInvestSheet) {
            if let opportunity {
                InvestProposalSheet(opportunity: opportunity) { amount in
                    guard let uid = auth.currentUserID else {
                        throw InvestmentService.InvestmentServiceError.notSignedIn
                    }
                    _ = try await investmentService.createInvestmentRequest(
                        opportunity: opportunity,
                        investorId: uid,
                        proposedAmount: amount
                    )
                    await MainActor.run {
                        Task { await loadMyRequest(for: opportunity) }
                    }
                }
                .environment(auth)
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ opportunity: OpportunityListing) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection(for: opportunity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(opportunity.title)
                        .font(.title2.bold())
                    if !opportunity.category.isEmpty {
                        Text(opportunity.category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(opportunity.status.uppercased())
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.tertiaryFill, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                divider
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                statBlock(title: "Funding goal", value: "LKR \(opportunity.formattedAmountLKR)")
                divider
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                statBlock(title: "Interest rate", value: "\(formatRate(opportunity.interestRate))%")
                divider
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                statBlock(title: "Repayment", value: opportunity.repaymentLabel)

                if let videoRef = opportunity.effectiveVideoReference {
                    divider
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Video")
                            .font(.headline)
                        StorageBackedVideoPlayer(
                            reference: videoRef,
                            height: 220,
                            cornerRadius: AppTheme.controlCornerRadius,
                            muted: false,
                            showsPlaybackControls: false,
                            allowFullscreenOnTap: false,
                            fullscreenPlaysMuted: false
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                } else if opportunity.mediaWarnings.contains(where: { $0.localizedCaseInsensitiveContains("video") }) {
                    divider
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    Text("Video did not upload — see Media notices below if shown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                if !opportunity.mediaWarnings.isEmpty {
                    divider
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Media notices")
                            .font(.headline)
                        ForEach(Array(opportunity.mediaWarnings.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                }

                if !opportunity.description.isEmpty {
                    divider
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this opportunity")
                            .font(.headline)
                        Text(opportunity.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    investActionBlock(for: opportunity)

                    Button {
                        Task { await openChatWithSeeker(opportunity: opportunity) }
                    } label: {
                        HStack {
                            if isOpeningChat {
                                ProgressView()
                                    .tint(AppTheme.accent)
                            }
                            Text("Contact seeker")
                                .font(.headline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            .stroke(AppTheme.accent, lineWidth: 1.5)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .disabled(isOpeningChat || !canContactSeeker(for: opportunity))
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .task(id: opportunity.id) {
            await loadMyRequest(for: opportunity)
        }
    }

    @ViewBuilder
    private func investActionBlock(for opportunity: OpportunityListing) -> some View {
        let status = myLatestRequest?.status.lowercased() ?? ""

        if auth.currentUserID == opportunity.ownerId {
            Text("This is your listing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if auth.currentUserID == nil {
            Text("Sign in to send an investment request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if status == "pending" {
            VStack(alignment: .leading, spacing: 6) {
                Text("Request sent")
                    .font(.headline.weight(.semibold))
                Text("Waiting for the seeker to accept or decline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else if status == "accepted" {
            VStack(alignment: .leading, spacing: 6) {
                Text("Request accepted")
                    .font(.headline.weight(.semibold))
                Text("Check the Invest tab for status and use Chat to coordinate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else {
            Button {
                showInvestSheet = true
            } label: {
                Text(status == "declined" || status == "rejected" ? "Send another request" : "Invest")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .foregroundStyle(.white)
        }
    }

    private func loadMyRequest(for opportunity: OpportunityListing) async {
        guard let uid = auth.currentUserID, uid != opportunity.ownerId else {
            await MainActor.run { myLatestRequest = nil }
            return
        }
        do {
            let latest = try await investmentService.fetchLatestRequestForInvestor(
                opportunityId: opportunity.id,
                investorId: uid
            )
            await MainActor.run { myLatestRequest = latest }
        } catch {
            await MainActor.run { myLatestRequest = nil }
        }
    }

    private func loadOpportunityFromServer() async {
        loadError = nil
        do {
            guard let fresh = try await opportunityService.fetchOpportunity(opportunityId: opportunityId) else {
                await MainActor.run {
                    loadError = "This listing may have been removed."
                    opportunity = nil
                }
                return
            }
            await MainActor.run {
                opportunity = fresh
            }
            await loadMyRequest(for: fresh)
        } catch {
            await MainActor.run {
                loadError = (error as NSError).localizedDescription
                opportunity = nil
            }
        }
    }

    private func canContactSeeker(for opportunity: OpportunityListing) -> Bool {
        guard let uid = auth.currentUserID else { return false }
        return uid != opportunity.ownerId
    }

    private func openChatWithSeeker(opportunity: OpportunityListing) async {
        guard let investorId = auth.currentUserID else {
            contactError = "Sign in to message the seeker."
            showContactError = true
            return
        }
        guard investorId != opportunity.ownerId else { return }

        isOpeningChat = true
        defer { isOpeningChat = false }

        do {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opportunity.id,
                seekerId: opportunity.ownerId,
                investorId: investorId,
                opportunityTitle: opportunity.title
            )
            activeChat = ActiveChatDestination(chatId: chatId, title: opportunity.title)
        } catch {
            contactError = error.localizedDescription
            showContactError = true
        }
    }

    private func heroSection(for opportunity: OpportunityListing) -> some View {
        Group {
            if opportunity.imageStoragePaths.isEmpty {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 280)
                    .overlay {
                        Image(systemName: opportunity.effectiveVideoReference != nil ? "play.rectangle.fill" : "photo")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
            } else {
                AutoPagingImageCarousel(
                    references: opportunity.imageStoragePaths,
                    height: 280,
                    cornerRadius: AppTheme.controlCornerRadius
                )
            }
        }
    }

    private func statBlock(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(Int(rate))
        }
        return String(rate)
    }
}

#Preview {
    NavigationStack {
        OpportunityDetailView(
            opportunity: OpportunityListing(
                id: "1",
                ownerId: "x",
                title: "Samsung phone",
                category: "Phone",
                description: "Meow",
                amountRequested: 150_000,
                interestRate: 11,
                repaymentTimelineMonths: 12,
                status: "open",
                createdAt: Date(),
                imageStoragePaths: [],
                videoStoragePath: nil,
                videoURL: nil,
                mediaWarnings: [],
                imagePublicIds: [],
                videoPublicId: nil
            )
        )
        .environment(AuthService.previewSignedIn)
    }
}
