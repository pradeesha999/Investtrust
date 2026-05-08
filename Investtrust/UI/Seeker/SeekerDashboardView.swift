//
//  SeekerDashboardView.swift
//  Investtrust
//
//  Seeker **Create** tab: guided listing creation and “my opportunities” management.
//

import SwiftUI

struct SeekerDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var showCreateFlow = false
    @State private var myOpportunities: [OpportunityListing] = []
    @State private var seekerInvestments: [InvestmentListing] = []
    @State private var selectedSegment: SeekerOpportunitySegment = .open
    @State private var opportunityFilterQuery = ""
    @State private var selectedInvestmentType: InvestmentType?
    @State private var fundingBracket: OpportunityFundingBracket = .any
    @State private var isLoading = false
    @State private var loadError: String?

    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()

    private var ongoingOpportunityIds: Set<String> {
        Set(seekerInvestments.compactMap { inv in
            guard let oid = inv.opportunityId, !oid.isEmpty else { return nil }
            let status = inv.status.lowercased()
            if status == "accepted" || status == "active" || inv.agreementStatus == .active || inv.agreementStatus == .pending_signatures {
                return oid
            }
            return nil
        })
    }

    private var completedOpportunityIds: Set<String> {
        Set(seekerInvestments.compactMap { inv in
            guard let oid = inv.opportunityId, !oid.isEmpty else { return nil }
            let status = inv.status.lowercased()
            if status == "completed" || inv.fundingStatus == .closed {
                return oid
            }
            return nil
        })
    }

    private var openOpportunities: [OpportunityListing] {
        myOpportunities.filter {
            !ongoingOpportunityIds.contains($0.id) && !completedOpportunityIds.contains($0.id)
        }
    }

    private var ongoingOpportunities: [OpportunityListing] {
        myOpportunities.filter {
            ongoingOpportunityIds.contains($0.id) && !completedOpportunityIds.contains($0.id)
        }
    }

    private var completedOpportunities: [OpportunityListing] {
        myOpportunities.filter { completedOpportunityIds.contains($0.id) }
    }

    private var displayedOpportunities: [OpportunityListing] {
        switch selectedSegment {
        case .open:
            return openOpportunities
        case .ongoing:
            return ongoingOpportunities
        case .completed:
            return completedOpportunities
        }
    }

    private var filteredDisplayedOpportunities: [OpportunityListing] {
        let query = opportunityFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = displayedOpportunities
        if let type = selectedInvestmentType {
            list = list.filter { $0.investmentType == type }
        }
        if fundingBracket != .any {
            list = list.filter { fundingBracket.contains(amount: $0.amountRequested) }
        }
        guard !query.isEmpty else { return list }
        return list.filter { item in
            item.title.lowercased().contains(query) || item.category.lowercased().contains(query)
        }
    }

    private var hasActiveOpportunityConstraints: Bool {
        !opportunityFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedInvestmentType != nil
            || fundingBracket != .any
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segment + search/filter — always sticky, never scrolls away
                if !myOpportunities.isEmpty {
                    VStack(spacing: 8) {
                        Picker("Opportunity status", selection: $selectedSegment) {
                            ForEach(SeekerOpportunitySegment.allCases, id: \.self) { segment in
                                Text(segment.title).tag(segment)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 26)

                        searchAndFilterBar
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.bottom, 8)
                    .background(Color(.systemGroupedBackground))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                        if myOpportunities.isEmpty {
                            headerCard
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
                                icon: "tray",
                                title: "No listings yet",
                                message: "Tap Add opportunity to publish your first investment request."
                            )
                        } else if displayedOpportunities.isEmpty {
                            StatusBlock(
                                icon: "tray",
                                title: selectedSegment == .open ? "No open opportunities" : (selectedSegment == .ongoing ? "No ongoing opportunities" : "No completed opportunities"),
                                message: selectedSegment == .open
                                    ? "Open listings will appear here."
                                    : (selectedSegment == .ongoing ? "Accepted deals in progress appear here." : "Finished deals appear here.")
                            )
                        } else if filteredDisplayedOpportunities.isEmpty {
                            StatusBlock(
                                icon: "line.3.horizontal.decrease.circle",
                                title: "No matches",
                                message: "Try a different keyword to filter opportunities."
                            )
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredDisplayedOpportunities) { item in
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
                .refreshable { await loadMyOpportunities() }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Opportunity")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadMyOpportunities() }
            .onAppear {
                selectedSegment = tabRouter.seekerOpportunitySegment
                consumeExternalCreateWizardIntentIfNeeded()
            }
            .onChange(of: selectedSegment) { _, newValue in
                tabRouter.seekerOpportunitySegment = newValue
                // Reset search/filter so each segment is independent
                opportunityFilterQuery = ""
                selectedInvestmentType = nil
                fundingBracket = .any
            }
            .onChange(of: tabRouter.seekerOpportunitySegment) { _, newValue in
                if selectedSegment != newValue {
                    selectedSegment = newValue
                }
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
            loadError = FirestoreUserFacingMessage.text(for: error)
        }
    }

    private func consumeExternalCreateWizardIntentIfNeeded() {
        guard tabRouter.openSeekerCreateWizard else { return }
        tabRouter.openSeekerCreateWizard = false
        showCreateFlow = true
    }

    private func resetOpportunityFilters() {
        opportunityFilterQuery = ""
        selectedInvestmentType = nil
        fundingBracket = .any
    }

    private var searchAndFilterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search opportunities", text: $opportunityFilterQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                if !opportunityFilterQuery.isEmpty {
                    Button {
                        opportunityFilterQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
            )

            Menu {
                if hasActiveOpportunityConstraints {
                    Button("Reset filters", role: .destructive) { resetOpportunityFilters() }
                }
                Section("Investment type") {
                    Picker("Type", selection: $selectedInvestmentType) {
                        Text("All types").tag(Optional<InvestmentType>.none)
                        ForEach(InvestmentType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                }
                Section("Funding goal") {
                    Picker("Funding goal", selection: $fundingBracket) {
                        ForEach(OpportunityFundingBracket.allCases) { b in
                            Text(b.menuTitle).tag(b)
                        }
                    }
                }
            } label: {
                Image(systemName: hasActiveOpportunityConstraints
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(hasActiveOpportunityConstraints ? auth.accentColor : .primary)
                    .padding(8)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
                    )
            }
        }
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
        let pendingRequests = pendingRequestCount(for: item.id)
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
                    if pendingRequests > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "bell.badge.fill")
                                .font(.caption.weight(.semibold))
                            Text(pendingRequests == 1 ? "1 new request" : "\(pendingRequests) new requests")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.red)
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
                    Text("Final return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(projectedFinalReturnText(for: item))
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

    private func projectedFinalReturnText(for item: OpportunityListing) -> String {
        let principal = item.amountRequested
        let rate = item.interestRate
        let months = item.repaymentTimelineMonths
        guard principal > 0, rate > 0, months > 0 else { return "—" }
        let total = LoanScheduleGenerator.totalRepayable(
            principal: principal,
            annualRatePercent: rate,
            termMonths: months
        )
        return "LKR \(OpportunityFinancialPreview.formatLKRInteger(total))"
    }

    private func pendingRequestCount(for opportunityId: String) -> Int {
        seekerInvestments.filter { inv in
            guard inv.opportunityId == opportunityId else { return false }
            return inv.status.lowercased() == "pending"
        }.count
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
