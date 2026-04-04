//
//  SeekerDashboardView.swift
//  Investtrust
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
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(item.category)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text("LKR \(item.formattedAmountLKR)")
                Spacer()
                Text("\(item.interestRate)%")
                Text("•")
                Text(item.repaymentLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if !item.imageStoragePaths.isEmpty {
                    Label("\(item.imageStoragePaths.count) image\(item.imageStoragePaths.count > 1 ? "s" : "")", systemImage: "photo.fill")
                }
                if item.effectiveVideoReference != nil {
                    Label("Video", systemImage: "video.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("Manage listing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.top, 4)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 1)
        )
    }
}

#Preview {
    SeekerDashboardView()
        .environment(AuthService.previewSignedIn)
}
