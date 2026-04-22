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

    private static let thumbnailSize: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 8) {
                    Text(inv.opportunityTitle.isEmpty ? "Investment" : inv.opportunityTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(inv.investmentType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(auth.accentColor)

                    Text(inv.lifecycleDisplayTitle)
                        .font(.caption)
                        .foregroundStyle(lifecycleColor(inv))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Amount: LKR \(format(inv.investmentAmount))")
                            .font(.subheadline)
                        Text("Interest: \(inv.interestLabel)")
                            .font(.subheadline)
                        Text("Timeline: \(inv.timelineLabel)")
                            .font(.subheadline)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }

            if let oid = inv.opportunityId, !oid.isEmpty {
                NavigationLink {
                    OpportunityDetailView(opportunityId: oid)
                } label: {
                    Text("View opportunity")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(auth.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                if let oid = inv.opportunityId, let iid = inv.investorId,
                   auth.currentUserID == iid {
                    Button {
                        let chatId = "\(oid)_\(iid)"
                        tabRouter.pendingChatDeepLink = ChatDeepLink(chatId: chatId)
                        tabRouter.selectedTab = .chat
                    } label: {
                        Text("Chat")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                } else {
                    Button {
                    } label: {
                        Text("Chat")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                    .disabled(true)
                }

                if inv.agreement != nil {
                    Button {
                        agreementToShow = inv
                    } label: {
                        Text(inv.needsInvestorSignature(currentUserId: auth.currentUserID) ? "Review & sign" : "Agreement")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                } else {
                    Button {
                    } label: {
                        Text("Agreement")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
            }

            if inv.isLoanWithSchedule {
                LoanInstallmentsSection(
                    investment: inv,
                    currentUserId: auth.currentUserID,
                    onRefresh: { await onRefreshLoan() }
                )
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
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

    /// Fixed-size thumbnail: `AsyncImage` + `scaledToFill` must be clipped inside an explicit frame or it can draw over sibling text.
    @ViewBuilder
    private var thumbnail: some View {
        let corner = RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        if let first = inv.imageURLs.first, let url = URL(string: first) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderFill
                case .empty:
                    Color(.systemGray5)
                @unknown default:
                    Color(.systemGray5)
                }
            }
            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
            .clipped()
            .clipShape(corner)
        } else {
            placeholderFill
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .clipShape(corner)
        }
    }

    private var placeholderFill: some View {
        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
            .fill(Color(.systemGray4))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
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

    private func format(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(Int(v))
    }
}
