//
//  OpportunityCard.swift
//  Investtrust
//

import SwiftUI

struct OpportunityCard: View {
    let opp: OpportunityListing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardMedia

            NavigationLink {
                OpportunityDetailView(opportunityId: opp.id)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
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

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Amount")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("LKR \(opp.formattedAmountLKR)")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Interest")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(opp.interestRate)%")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Timeline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(opp.repaymentLabel)
                                .font(.subheadline.weight(.semibold))
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
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    @ViewBuilder
    private var cardMedia: some View {
        if let video = opp.effectiveVideoReference {
            StorageBackedVideoPlayer(
                reference: video,
                height: 190,
                cornerRadius: 16,
                muted: true,
                showsPlaybackControls: false,
                allowFullscreenOnTap: true,
                fullscreenPlaysMuted: false
            )
        } else if opp.imageStoragePaths.count > 1 {
            NavigationLink {
                OpportunityDetailView(opportunityId: opp.id)
            } label: {
                AutoPagingImageCarousel(references: opp.imageStoragePaths, height: 190, cornerRadius: 16)
            }
            .buttonStyle(.plain)
        } else if let first = opp.imageStoragePaths.first {
            NavigationLink {
                OpportunityDetailView(opportunityId: opp.id)
            } label: {
                StorageBackedAsyncImage(reference: first, height: 190, cornerRadius: 16)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                OpportunityDetailView(opportunityId: opp.id)
            } label: {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 190)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}
