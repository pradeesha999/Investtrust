//
//  InvestmentCard.swift
//  Investtrust
//

import SwiftUI

struct InvestmentCard: View {
    let inv: InvestmentListing
    /// Reload parent list after installment or proof actions (optional).
    var onRefreshLoan: () async -> Void = {}

    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var agreementToShow: InvestmentListing?
    @State private var chatLoadError: String?
    @State private var showChatLoadError = false
    private let investmentService = InvestmentService()
    private let chatService = ChatService()
    private let opportunityService = OpportunityService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardMedia

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(inv.opportunityTitle.isEmpty ? "Investment" : inv.opportunityTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(inv.investmentType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let rate = inv.finalInterestRate, rate > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(formatRate(rate))%")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(auth.accentColor)
                        Text("Interest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                cardChip(inv.investmentType.displayName)
                statusBadge(inv.lifecycleDisplayTitle, tint: lifecycleColor(inv))
                Spacer(minLength: 0)
                if let created = inv.createdAt {
                    Label(shortDate(created), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Funding goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("LKR \(format(inv.investmentAmount))")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Final return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(finalReturnText)
                        .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timeline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(inv.timelineLabel)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                if canOpenChat {
                    Button {
                        Task { await openChat() }
                    } label: {
                        Text("Chat")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                }

                if inv.agreement != nil {
                    Button {
                        agreementToShow = inv
                    } label: {
                        Text(inv.needsInvestorSignature(currentUserId: auth.currentUserID) ? "Review & sign" : "Agreement")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                }
            }

            if let oid = inv.opportunityId, !oid.isEmpty {
                NavigationLink {
                    OpportunityDetailView(opportunityId: oid)
                } label: {
                    HStack {
                        Text("View opportunity")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(auth.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
        .appCardShadow()
        .sheet(item: $agreementToShow) { row in
            NavigationStack {
                InvestmentAgreementReviewView(
                    investment: row,
                    canSign: row.needsInvestorSignature(currentUserId: auth.currentUserID),
                    onSign: { signaturePNG in
                        guard let uid = auth.currentUserID else {
                            throw InvestmentService.InvestmentServiceError.notSignedIn
                        }
                        do {
                            try await investmentService.signAgreement(
                                investmentId: row.id,
                                userId: uid,
                                signaturePNG: signaturePNG
                            )
                            await onRefreshLoan()
                        } catch {
                            await onRefreshLoan()
                            throw error
                        }
                    }
                )
            }
        }
        .alert("Could not open chat", isPresented: $showChatLoadError) {
            Button("OK") { chatLoadError = nil }
        } message: {
            Text(chatLoadError ?? "")
        }
    }

    @ViewBuilder
    private var cardMedia: some View {
        if let first = inv.imageURLs.first, let url = URL(string: first) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    mediaPlaceholder
                case .empty:
                    Color(.systemGray5)
                @unknown default:
                    Color(.systemGray5)
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            mediaPlaceholder
                .frame(height: 190)
        }
    }

    private var mediaPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    private func cardChip(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint == .secondary ? AppTheme.secondaryFill : tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint == .secondary ? .primary : tint)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func lifecycleColor(_ inv: InvestmentListing) -> Color {
        switch inv.agreementStatus {
        case .active:
            return .green
        case .pending_signatures:
            return .orange
        case .none:
            break
        }
        switch inv.status.lowercased() {
        case "pending": return .orange
        case "accepted", "active": return .green
        case "declined", "rejected": return .red
        default: return .secondary
        }
    }

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    private func format(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(Int(v))
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(Int(rate))
        }
        return String(format: "%.1f", rate)
    }

    private var finalReturnText: String {
        let principal = max(0, inv.investmentAmount)
        let rate = max(0, inv.finalInterestRate ?? inv.agreement?.termsSnapshot.interestRate ?? 0)
        let months = max(0, inv.finalTimelineMonths ?? inv.agreement?.termsSnapshot.effectiveTimelineMonths ?? 0)
        guard principal > 0, rate > 0, months > 0 else { return "—" }
        let total = LoanScheduleGenerator.totalRepayable(
            principal: principal,
            annualRatePercent: rate,
            termMonths: months
        )
        return "LKR \(OpportunityFinancialPreview.formatLKRInteger(total))"
    }

    private var canOpenChat: Bool {
        // Keep chat available for investor rows even when legacy documents miss one of the ids.
        auth.currentUserID != nil && (inv.offerChatId != nil || inv.opportunityId != nil)
    }

    private func openChat() async {
        guard let currentUserId = auth.currentUserID else { return }
        do {
            if let existingChatId = inv.offerChatId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !existingChatId.isEmpty {
                await MainActor.run {
                    tabRouter.pendingChatDeepLink = ChatDeepLink(chatId: existingChatId)
                    tabRouter.selectedTab = .chat
                }
                return
            }

            guard let opportunityId = inv.opportunityId, !opportunityId.isEmpty else {
                throw NSError(
                    domain: "Investtrust",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "This row has no linked opportunity for chat."]
                )
            }
            let investorId = (inv.investorId?.isEmpty == false) ? inv.investorId! : currentUserId
            guard investorId == currentUserId else {
                throw NSError(
                    domain: "Investtrust",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Only the investor can open this conversation."]
                )
            }

            let seekerId: String
            if let existing = inv.seekerId, !existing.isEmpty {
                seekerId = existing
            } else if let opp = try await opportunityService.fetchOpportunity(opportunityId: opportunityId) {
                seekerId = opp.ownerId
            } else {
                throw NSError(
                    domain: "Investtrust",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to resolve the opportunity owner for chat."]
                )
            }

            let title = inv.opportunityTitle.isEmpty ? "Investment" : inv.opportunityTitle
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opportunityId,
                seekerId: seekerId,
                investorId: investorId,
                opportunityTitle: title
            )
            await MainActor.run {
                tabRouter.pendingChatDeepLink = ChatDeepLink(chatId: chatId)
                tabRouter.selectedTab = .chat
            }
        } catch {
            await MainActor.run {
                chatLoadError = (error as NSError).localizedDescription
                showChatLoadError = true
            }
        }
    }
}
