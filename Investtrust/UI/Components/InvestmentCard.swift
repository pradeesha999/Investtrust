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
    private let investmentService = InvestmentService()
    private let chatService = ChatService()

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
                statusBadge(inv.lifecycleDisplayTitle, tint: lifecycleColor(inv))
            }

            HStack(spacing: 8) {
                cardChip("Invested")
                cardChip("LKR \(format(inv.investmentAmount))", tint: auth.accentColor)
                cardChip(inv.interestLabel)
                cardChip(inv.timelineLabel)
                Spacer(minLength: 0)
                if let created = inv.createdAt {
                    Label(shortDate(created), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if let oid = inv.opportunityId, !oid.isEmpty,
                   let investorId = inv.investorId,
                   let seekerId = inv.seekerId,
                   auth.currentUserID == investorId {
                    Button {
                        Task {
                            do {
                                let chatId = try await chatService.getOrCreateChat(
                                    opportunityId: oid,
                                    seekerId: seekerId,
                                    investorId: investorId,
                                    opportunityTitle: inv.opportunityTitle
                                )
                                await MainActor.run {
                                    tabRouter.pendingChatDeepLink = ChatDeepLink(chatId: chatId)
                                    tabRouter.selectedTab = .chat
                                }
                            } catch {
                                // no-op in card action
                            }
                        }
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

            if inv.isLoanWithSchedule {
                LoanInstallmentsSection(
                    investment: inv,
                    currentUserId: auth.currentUserID,
                    onRefresh: { await onRefreshLoan() }
                )
            } else if inv.isRevenueShareWithSchedule {
                RevenueSharePeriodsSection(
                    investment: inv,
                    currentUserId: auth.currentUserID,
                    onRefresh: { await onRefreshLoan() }
                )
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
}
