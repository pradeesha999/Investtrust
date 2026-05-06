//
//  OpportunityCard.swift
//  Investtrust
//

import SwiftUI

struct OpportunityCard: View {
    @Environment(AuthService.self) private var auth

    let opp: OpportunityListing
    var statusOverride: String? = nil

    var body: some View {
        NavigationLink {
            OpportunityDetailView(opportunity: opp)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                cardMedia

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(opp.title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        if !opp.category.isEmpty {
                            Text(opp.category)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if opp.interestRate > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(formatRate(opp.interestRate))%")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(auth.accentColor)
                            Text("Interest")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(opp.investmentType.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.secondaryFill, in: Capsule())
                    let statusText = statusOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? statusOverride!
                        : opp.status.capitalized
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor(statusText).opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor(statusText))
                    if let createdAt = opp.createdAt {
                        Label(shortDate(createdAt), systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Funding goal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("LKR \(opp.formattedAmountLKR)")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Final return")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(projectedFinalReturnText)
                            .font(.caption.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(opp.maximumInvestors.map { "\($0) investors" } ?? "Open")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }

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
        }
        .buttonStyle(.plain)
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
        )
        .appCardShadow()
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(Int(rate))
        }
        return String(format: "%.1f", rate)
    }

    private func statusColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "open": return .green
        case "request pending": return .orange
        case "closed", "filled", "funded": return .secondary
        default: return .primary
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private var projectedFinalReturnText: String {
        let principal = opp.amountRequested
        let rate = opp.interestRate
        let months = opp.repaymentTimelineMonths
        guard principal > 0, rate > 0, months > 0 else { return "—" }
        let total = LoanScheduleGenerator.totalRepayable(
            principal: principal,
            annualRatePercent: rate,
            termMonths: months
        )
        return "LKR \(OpportunityFinancialPreview.formatLKRInteger(total))"
    }

    /// Feed: images only (first photo, Cloudinary-thumbnail when applicable). Video plays on the detail screen — never load a player here.
    @ViewBuilder
    private var cardMedia: some View {
        if let first = opp.imageStoragePaths.first {
            StorageBackedAsyncImage(
                reference: first,
                height: 190,
                cornerRadius: 16,
                feedThumbnail: true
            )
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray5))
                .frame(height: 190)
                .overlay {
                    Image(systemName: opp.effectiveVideoReference != nil ? "play.rectangle.fill" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
