//
//  OpportunityCard.swift
//  Investtrust
//

import SwiftUI

struct OpportunityCard: View {
    let opp: OpportunityListing

    var body: some View {
        NavigationLink {
            OpportunityDetailView(opportunityId: opp.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                cardMedia

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

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amount")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("LKR \(opp.formattedAmountLKR)")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Type")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(opp.investmentType.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Key terms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(opp.termsSummaryLine)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }

                if !opp.description.isEmpty {
                    Text(opp.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("View more")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
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
