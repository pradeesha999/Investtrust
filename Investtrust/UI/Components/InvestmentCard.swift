//
//  InvestmentCard.swift
//  Investtrust
//

import SwiftUI

struct InvestmentCard: View {
    let inv: InvestmentListing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                media
                    .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    Text(inv.opportunityTitle.isEmpty ? "Investment" : inv.opportunityTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Text(inv.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                Button {
                    // Hook: route to chat when thread id is available on investment.
                } label: {
                    Text("Chat")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
                .disabled(true)
                .accessibilityLabel("Chat, coming soon")

                Button {
                    // Hook: agreement documents.
                } label: {
                    Text("Agreement")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
                .accessibilityLabel("Agreement, coming soon")
            }

            Text("Chat and agreement actions will connect here in a future update.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.85))
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
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

    private func format(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(Int(v))
    }
}
