//
//  SeekerDashboardView.swift
//  Investtrust
//
//  Seeker **Create** tab: guided listing creation and “my opportunities” management.
//

import SwiftUI

private enum SeekerOpportunitySegment: String, CaseIterable {
    case open
    case ongoing

    var title: String {
        switch self {
        case .open: return "Open"
        case .ongoing: return "Ongoing"
        }
    }
}

struct SeekerDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var showCreateFlow = false
    @State private var myOpportunities: [OpportunityListing] = []
    @State private var seekerInvestments: [InvestmentListing] = []
    @State private var selectedSegment: SeekerOpportunitySegment = .open
    @State private var isLoading = false
    @State private var loadError: String?

    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()

    private var ongoingOpportunityIds: Set<String> {
        Set(seekerInvestments.compactMap { inv in
            guard let oid = inv.opportunityId, !oid.isEmpty else { return nil }
            let status = inv.status.lowercased()
            if status == "accepted" || status == "active" || status == "completed" || inv.agreementStatus != .none {
                return oid
            }
            return nil
        })
    }

    private var openOpportunities: [OpportunityListing] {
        myOpportunities.filter { !ongoingOpportunityIds.contains($0.id) }
    }

    private var ongoingOpportunities: [OpportunityListing] {
        myOpportunities.filter { ongoingOpportunityIds.contains($0.id) }
    }

    private var displayedOpportunities: [OpportunityListing] {
        selectedSegment == .open ? openOpportunities : ongoingOpportunities
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                    if myOpportunities.isEmpty {
                        headerCard
                    }

                    if !myOpportunities.isEmpty {
                        Picker("Opportunity status", selection: $selectedSegment) {
                            ForEach(SeekerOpportunitySegment.allCases, id: \.self) { segment in
                                Text(segment.title).tag(segment)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)
                    } else {
                        Text("Opportunities")
                            .font(.headline)
                            .padding(.top, 4)
                    }

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
                    } else if displayedOpportunities.isEmpty {
                        StatusBlock(
                            icon: selectedSegment == .open ? "tray" : "hourglass",
                            title: selectedSegment == .open ? "No open opportunities" : "No ongoing opportunities",
                            message: selectedSegment == .open
                                ? "Accepted deals will move to the Ongoing tab."
                                : "Once a request is accepted, it will appear here."
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(displayedOpportunities) { item in
                                NavigationLink {
                                    SeekerOpportunityDetailView(
                                        opportunity: item,
                                        onMutate: {
                                            Task { await loadMyOpportunities() }
                                        },
                                        onAcceptedRequest: {
                                            selectedSegment = .ongoing
                                            Task { await loadMyOpportunities() }
                                        }
                                    )
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
            .navigationTitle("Opportunity")
            .task { await loadMyOpportunities() }
            .refreshable { await loadMyOpportunities() }
            .onAppear {
                consumeExternalCreateWizardIntentIfNeeded()
            }
            .onChange(of: tabRouter.openSeekerCreateWizard) { _, _ in
                consumeExternalCreateWizardIntentIfNeeded()
            }
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
            .overlay(alignment: .bottomTrailing) {
                if !myOpportunities.isEmpty {
                    Button {
                        showCreateFlow = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                            .frame(width: 56, height: 56)
                            .background(auth.accentColor, in: Circle())
                            .foregroundStyle(.white)
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, AppTheme.screenPadding)
                    .padding(.bottom, 20)
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
            async let opps = opportunityService.fetchSeekerListings(ownerId: userID)
            async let invs = investmentService.fetchInvestmentsForSeeker(seekerId: userID)
            myOpportunities = try await opps
            seekerInvestments = try await invs
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func consumeExternalCreateWizardIntentIfNeeded() {
        guard tabRouter.openSeekerCreateWizard else { return }
        tabRouter.openSeekerCreateWizard = false
        showCreateFlow = true
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create an opportunity")
                .font(.title3.bold())
            Text("Use the guided form to publish a new listing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showCreateFlow = true
            } label: {
                Label("Add opportunity", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minTapTarget)
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
        let statusText = item.status.capitalized
        return VStack(alignment: .leading, spacing: 12) {
            seekerRowMedia(item)

            HStack(alignment: .top, spacing: 10) {
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
                Spacer(minLength: 8)
                if item.interestRate > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(formatRate(item.interestRate))%")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(auth.accentColor)
                        Text("Interest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Text(item.investmentType.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.secondaryFill, in: Capsule())
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor(item.status).opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor(item.status))
                if let createdAt = item.createdAt {
                    Label(shortDate(createdAt), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Funding goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("LKR \(item.formattedAmountLKR)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Min ticket")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("LKR \(item.formattedMinimumLKR)")
                        .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capacity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.maximumInvestors.map { "\($0) investors" } ?? "Open")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }

            HStack {
                Text("Manage listing")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(auth.accentColor)
        }
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
        case "closed", "filled", "funded": return .secondary
        default: return .primary
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
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
