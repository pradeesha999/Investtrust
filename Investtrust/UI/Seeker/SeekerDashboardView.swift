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
            VStack(spacing: 16) {
                headerCard
                opportunitiesList
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Seeker Dashboard")
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
                Label("Add Opportunity", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
    }

    private var opportunitiesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Opportunities")
                .font(.headline)

            if let loadError {
                Text(loadError)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
            } else if isLoading && myOpportunities.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
                    .padding(14)
            } else if myOpportunities.isEmpty {
                Text("No opportunities yet. Tap \"Add Opportunity\" to create your first listing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(myOpportunities) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
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
                                    if item.videoStoragePath != nil {
                                        Label("Video", systemImage: "video.fill")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SeekerDashboardView()
        .environment(AuthService.previewSignedIn)
}

