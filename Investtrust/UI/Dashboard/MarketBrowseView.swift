import SwiftUI

/// Open market listings (browse) — not the investor portfolio dashboard.
struct MarketBrowseView: View {
    /// When true, hides its own navigation title (used inside `InvestorActionTabView` segmented **Explore**).
    var embeddedInInvestTab: Bool = false

    @Environment(AuthService.self) private var auth

    @State private var opportunities: [OpportunityListing] = []
    @State private var myLatestRequestsByOpportunityId: [String: InvestmentListing] = [:]
    @State private var isLoading = false
    @State private var loadError: String?

    // Explore-only (embedded tab): search + filters
    @State private var searchText = ""
    @State private var selectedInvestmentType: InvestmentType?
    @State private var selectedRisk: RiskLevel?
    @State private var verifiedOnly = false
    @State private var sortOption: MarketExploreSort = .newest

    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()

    var body: some View {
        scrollContent
            .background(Color(.systemGroupedBackground))
            .modifier(EmbeddedNavigationTitleModifier(embedded: embeddedInInvestTab))
            .task { await load() }
            .refreshable { await load() }
            .if(embeddedInInvestTab) { view in
                view
                    .searchable(text: $searchText, prompt: "Search title, category, location")
                    .toolbar { exploreFiltersToolbar }
            }
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                if isLoading && opportunities.isEmpty {
                    ProgressView("Loading opportunities…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if let loadError {
                    StatusBlock(
                        icon: "exclamationmark.triangle.fill",
                        title: "Couldn't load opportunities",
                        message: loadError,
                        iconColor: .orange,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                } else if opportunities.isEmpty {
                    StatusBlock(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No open opportunities yet",
                        message: "Listings will appear here once seekers publish opportunities."
                    )
                } else if embeddedInInvestTab && filteredOpportunities.isEmpty {
                    StatusBlock(
                        icon: "magnifyingglass",
                        title: "No matching listings",
                        message: "Try another search or adjust filters.",
                        actionTitle: hasActiveExploreConstraints ? "Reset filters" : nil,
                        action: hasActiveExploreConstraints ? { resetExploreFilters() } : nil
                    )
                } else {
                    LazyVStack(spacing: AppTheme.stackSpacing) {
                        ForEach(displayedOpportunities, id: \.id) { opp in
                            OpportunityCard(
                                opp: opp,
                                statusOverride: statusOverride(for: opp)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    /// Rows shown in the list: raw server order when not embedded; filtered + sorted in Invest **Explore**.
    private var displayedOpportunities: [OpportunityListing] {
        embeddedInInvestTab ? filteredOpportunities : opportunities
    }

    private var filteredOpportunities: [OpportunityListing] {
        var list = opportunities
        if let t = selectedInvestmentType {
            list = list.filter { $0.investmentType == t }
        }
        if let r = selectedRisk {
            list = list.filter { $0.riskLevel == r }
        }
        if verifiedOnly {
            list = list.filter { $0.verificationStatus == .verified }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter { opp in
                opp.title.localizedCaseInsensitiveContains(q)
                    || opp.category.localizedCaseInsensitiveContains(q)
                    || opp.location.localizedCaseInsensitiveContains(q)
                    || opp.description.localizedCaseInsensitiveContains(q)
            }
        }
        switch sortOption {
        case .newest:
            list.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .amountHigh:
            list.sort { $0.amountRequested > $1.amountRequested }
        case .amountLow:
            list.sort { $0.amountRequested < $1.amountRequested }
        }
        return list
    }

    private var hasActiveExploreConstraints: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedInvestmentType != nil
            || selectedRisk != nil
            || verifiedOnly
            || sortOption != .newest
    }

    @ToolbarContentBuilder
    private var exploreFiltersToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if hasActiveExploreConstraints {
                    Button("Reset filters") { resetExploreFilters() }
                }
                Section("Sort") {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(MarketExploreSort.allCases, id: \.self) { s in
                            Text(s.title).tag(s)
                        }
                    }
                }
                Section("Investment type") {
                    Picker("Type", selection: $selectedInvestmentType) {
                        Text("All types").tag(Optional<InvestmentType>.none)
                        ForEach(InvestmentType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(Optional(t))
                        }
                    }
                }
                Section("Risk") {
                    Picker("Risk", selection: $selectedRisk) {
                        Text("Any risk").tag(Optional<RiskLevel>.none)
                        ForEach(RiskLevel.allCases, id: \.self) { r in
                            Text(r.displayName).tag(Optional(r))
                        }
                    }
                }
                Section("Verification") {
                    Toggle("Verified seekers only", isOn: $verifiedOnly)
                }
            } label: {
                Label("Filters", systemImage: hasActiveExploreConstraints ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filters and sort")
        }
    }

    private func resetExploreFilters() {
        searchText = ""
        selectedInvestmentType = nil
        selectedRisk = nil
        verifiedOnly = false
        sortOption = .newest
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await opportunityService.fetchMarketListings()
            if let userID = auth.currentUserID {
                opportunities = all.filter { $0.ownerId != userID }
                let myInvestments = try await investmentService.fetchInvestments(forInvestor: userID)
                myLatestRequestsByOpportunityId = latestRequestsMap(from: myInvestments)
            } else {
                opportunities = all
                myLatestRequestsByOpportunityId = [:]
            }
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func latestRequestsMap(from rows: [InvestmentListing]) -> [String: InvestmentListing] {
        var map: [String: InvestmentListing] = [:]
        for row in rows {
            guard let oppId = row.opportunityId, !oppId.isEmpty else { continue }
            if let existing = map[oppId] {
                if (row.createdAt ?? .distantPast) > (existing.createdAt ?? .distantPast) {
                    map[oppId] = row
                }
            } else {
                map[oppId] = row
            }
        }
        return map
    }

    private func statusOverride(for opp: OpportunityListing) -> String? {
        guard let request = myLatestRequestsByOpportunityId[opp.id] else { return nil }
        if request.agreementStatus == .pending_signatures {
            return "Request pending"
        }
        if request.status.lowercased() == "accepted" {
            return "Request pending"
        }
        return nil
    }
}

// MARK: - Explore sort

private enum MarketExploreSort: String, CaseIterable {
    case newest
    case amountHigh
    case amountLow

    var title: String {
        switch self {
        case .newest: return "Newest first"
        case .amountHigh: return "Highest amount"
        case .amountLow: return "Lowest amount"
        }
    }
}

// MARK: - Navigation + conditional view helpers

private struct EmbeddedNavigationTitleModifier: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .navigationTitle("Explore")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    NavigationStack {
        MarketBrowseView()
            .environment(AuthService.previewSignedIn)
    }
}
