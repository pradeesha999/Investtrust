//
//  InvestmentCard.swift
//  Investtrust
//

import SwiftUI

struct InvestmentCard: View {
    let inv: InvestmentListing

    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var agreementToShow: InvestmentListing?
    private let investmentService = InvestmentService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                media
                    .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    Text(inv.opportunityTitle.isEmpty ? "Investment" : inv.opportunityTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Text(inv.investmentType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)

                    Text(inv.lifecycleDisplayTitle)
                        .font(.caption)
                        .foregroundStyle(lifecycleColor(inv))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amount: LKR \(format(inv.investmentAmount))")
                            .font(.subheadline)
                        Text("Interest: \(inv.interestLabel)")
                            .font(.subheadline)
                        Text("Timeline: \(inv.timelineLabel)")
                            .font(.subheadline)
                    }
                }
            }

            if let oid = inv.opportunityId, !oid.isEmpty {
                NavigationLink {
                    OpportunityDetailView(opportunityId: oid)
                } label: {
                    Text("View opportunity")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accent, in: Capsule())
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
                    .tint(AppTheme.accent)
                } else {
                    Button {
                    } label: {
                        Text("Chat")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
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
                    .tint(AppTheme.accent)
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
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
        .sheet(item: $agreementToShow) { row in
            InvestmentAgreementReviewView(
                investment: row,
                canSign: row.needsInvestorSignature(currentUserId: auth.currentUserID),
                onSign: {
                    guard let uid = auth.currentUserID else {
                        throw InvestmentService.InvestmentServiceError.notSignedIn
                    }
                    try await investmentService.signAgreement(investmentId: row.id, userId: uid)
                }
            )
        }
    }

    @ViewBuilder
    private var media: some View {
        if let first = inv.imageURLs.first, let url = URL(string: first) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color(.systemGray4)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .fill(Color(.systemGray4))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
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
