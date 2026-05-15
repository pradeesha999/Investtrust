import SwiftUI

// The "Explore" market feed showing open opportunity listings.
// Can run standalone or embedded inside the investor Invest tab with search/filter state owned by the parent.
struct MarketBrowseView: View {
    // When true the parent (InvestorActionTabView) provides search/filter state instead of this view managing it
    var embeddedInInvestTab: Bool = false

    var externalSearchText: String = ""
    var externalInvestmentType: InvestmentType? = nil
    var externalFundingBracket: OpportunityFundingBracket = .any
    var externalSort: MarketExploreSort = .newest

    @Environment(AuthService.self) private var auth

    @State private var opportunities: [OpportunityListing] = []
    @State private var myLatestRequestsByOpportunityId: [String: InvestmentListing] = [:]
    @State private var isLoading = false
    @State private var loadError: String?

    // Only used when NOT embedded (standalone browse).
    @State private var searchText = ""
    @State private var selectedInvestmentType: InvestmentType?
    @State private var fundingBracket: OpportunityFundingBracket = .any
    @State private var sortOption: MarketExploreSort = .newest

    private var activeSearchText: String { embeddedInInvestTab ? externalSearchText : searchText }
    private var activeInvestmentType: InvestmentType? { embeddedInInvestTab ? externalInvestmentType : selectedInvestmentType }
    private var activeFundingBracket: OpportunityFundingBracket { embeddedInInvestTab ? externalFundingBracket : fundingBracket }
    private var activeSortOption: MarketExploreSort { embeddedInInvestTab ? externalSort : sortOption }

    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()

    var body: some View {
        scrollContent
            .background(Color(.systemGroupedBackground))
            .modifier(EmbeddedNavigationTitleModifier(embedded: embeddedInInvestTab))
            .task { await load() }
            .refreshable { await load() }
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                if !embeddedInInvestTab {
                    exploreSearchAndFilterBar
                }

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

    // Rows shown in the list: raw server order when not embedded; filtered + sorted in Invest **Explore**.
    private var displayedOpportunities: [OpportunityListing] {
        embeddedInInvestTab ? filteredOpportunities : opportunities
    }

    private var filteredOpportunities: [OpportunityListing] {
        var list = opportunities
        if let t = activeInvestmentType {
            list = list.filter { $0.investmentType == t }
        }
        if activeFundingBracket != .any {
            list = list.filter { activeFundingBracket.contains(amount: $0.amountRequested) }
        }
        let q = activeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter { opp in
                opp.title.localizedCaseInsensitiveContains(q)
                    || opp.category.localizedCaseInsensitiveContains(q)
                    || opp.location.localizedCaseInsensitiveContains(q)
                    || opp.description.localizedCaseInsensitiveContains(q)
            }
        }
        switch activeSortOption {
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
        !activeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || activeInvestmentType != nil
            || activeFundingBracket != .any
            || activeSortOption != .newest
    }

    private func resetExploreFilters() {
        searchText = ""
        selectedInvestmentType = nil
        fundingBracket = .any
        sortOption = .newest
    }

    @ViewBuilder
    private var exploreSearchAndFilterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search title, category, location", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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
                if hasActiveExploreConstraints {
                    Button("Reset filters", role: .destructive) { resetExploreFilters() }
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
                Section("Funding goal") {
                    Picker("Funding goal", selection: $fundingBracket) {
                        ForEach(OpportunityFundingBracket.allCases) { b in
                            Text(b.menuTitle).tag(b)
                        }
                    }
                }
            } label: {
                Image(systemName: hasActiveExploreConstraints
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(hasActiveExploreConstraints ? auth.accentColor : .primary)
                    .padding(8)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await opportunityService.fetchMarketListings()
            if let userID = auth.currentUserID {
                let myInvestments = try await investmentService.fetchInvestments(forInvestor: userID)
                let ongoingOpportunityIds = Set(
                    myInvestments.compactMap { row -> String? in
                        guard InvestorPortfolioMetrics.isOngoingPortfolioRow(row) else { return nil }
                        guard let oppId = row.opportunityId, !oppId.isEmpty else { return nil }
                        return oppId
                    }
                )
                let completedOpportunityIds = Set(
                    myInvestments.compactMap { row -> String? in
                        guard InvestorPortfolioMetrics.isCompletedDeal(row) else { return nil }
                        guard let oppId = row.opportunityId, !oppId.isEmpty else { return nil }
                        return oppId
                    }
                )
                opportunities = all.filter {
                    $0.ownerId != userID
                        && !ongoingOpportunityIds.contains($0.id)
                        && !completedOpportunityIds.contains($0.id)
                }
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
        // Ongoing / live deals use the Ongoing tab; don’t drive Explore badges from them.
        let pipeline = rows.filter { !InvestorPortfolioMetrics.isOngoingPortfolioRow($0) }
        var map: [String: InvestmentListing] = [:]
        for row in pipeline {
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

// Explore sort

enum MarketExploreSort: String, CaseIterable {
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

// Navigation + conditional view helpers

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
