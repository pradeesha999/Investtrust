//
//  SeekerDashboardView.swift
//  Investtrust
//
//  Seeker **Create** tab: guided listing creation and “my opportunities” management.
//

import SwiftUI

struct SeekerDashboardView: View {
    @Environment(AuthService.self) private var auth
    @State private var showCreateFlow = false
    @State private var myOpportunities: [OpportunityListing] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let opportunityService = OpportunityService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                    headerCard

                    Text("My opportunities")
                        .font(.headline)
                        .padding(.top, 4)

                    if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(AppTheme.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                            .appCardShadow()
                    } else if isLoading && myOpportunities.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else if myOpportunities.isEmpty {
                        StatusBlock(
                            icon: "plus.app",
                            title: "No listings yet",
                            message: "Tap Add opportunity to publish your first investment request."
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(myOpportunities) { item in
                                NavigationLink {
                                    SeekerOpportunityDetailView(opportunity: item) {
                                        Task { await loadMyOpportunities() }
                                    }
                                } label: {
                                    seekerListingRow(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(AppTheme.screenPadding)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Create")
            .task { await loadMyOpportunities() }
            .refreshable { await loadMyOpportunities() }
            .sheet(isPresented: $showCreateFlow) {
                CreateOpportunityWizardView { draft, imageDataList, videoData in
                    guard let userID = auth.currentUserID else {
                        throw NSError(domain: "Investtrust", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please sign in again."])
                    }
                    _ = try await opportunityService.createOpportunity(
                        userID: userID,
                        draft: draft,
                        imageDataList: imageDataList,
                        videoData: videoData
                    )
                    await loadMyOpportunities()
                }
            }
        }
    }

    private func loadMyOpportunities() async {
        guard let userID = auth.currentUserID else { return }
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            myOpportunities = try await opportunityService.fetchSeekerListings(ownerId: userID)
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create investment opportunities")
                .font(.title3.bold())
            Text("Post one opportunity at a time using a guided step-by-step form.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showCreateFlow = true
            } label: {
                Label("Add opportunity", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func seekerListingRow(_ item: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            seekerRowMedia(item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if !item.category.isEmpty {
                    Text(item.category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("LKR \(item.formattedAmountLKR)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.investmentType.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key terms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.termsSummaryLine)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("Manage listing")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(auth.accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    @ViewBuilder
    private func seekerRowMedia(_ item: OpportunityListing) -> some View {
        if let first = item.imageStoragePaths.first {
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
                    Image(systemName: item.effectiveVideoReference != nil ? "play.rectangle.fill" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    SeekerDashboardView()
        .environment(AuthService.previewSignedIn)
}
