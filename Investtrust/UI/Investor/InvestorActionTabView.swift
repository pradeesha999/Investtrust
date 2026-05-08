import SwiftUI

/// Investor **Invest** tab: Explore, requests pipeline, live deals, and completed deals.
struct InvestorActionTabView: View {
    @EnvironmentObject private var tabRouter: MainTabRouter
    @Environment(AuthService.self) private var auth

    // Shared search — reset when segment changes so each tab is independent.
    @State private var searchText = ""

    // Explore-only filters
    @State private var exploreType: InvestmentType?
    @State private var exploreFundingBracket: OpportunityFundingBracket = .any
    @State private var exploreSort: MarketExploreSort = .newest

    private var segmentBinding: Binding<InvestorInvestSegment> {
        Binding(
            get: { tabRouter.investorInvestSegment },
            set: { tabRouter.investorInvestSegment = $0 }
        )
    }

    private var hasActiveConstraints: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (tabRouter.investorInvestSegment == .explore && (exploreType != nil || exploreFundingBracket != .any || exploreSort != .newest))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segment picker
                Picker("Invest mode", selection: segmentBinding) {
                    ForEach(InvestorInvestSegment.allCases, id: \.self) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 26)
                .padding(.bottom, 8)

                // Static search + filter bar — always visible, no animation
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        TextField(searchPrompt, text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
                    )

                    Menu {
                        filterMenuContent
                    } label: {
                        Image(systemName: hasActiveConstraints
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundStyle(hasActiveConstraints ? auth.accentColor : .primary)
                            .padding(8)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                                    .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.bottom, 8)

                // Tab content
                Group {
                    switch tabRouter.investorInvestSegment {
                    case .myRequests:
                        InvestorMarketView(searchText: searchText)
                    case .explore:
                        MarketBrowseView(
                            embeddedInInvestTab: true,
                            externalSearchText: searchText,
                            externalInvestmentType: exploreType,
                            externalFundingBracket: exploreFundingBracket,
                            externalSort: exploreSort
                        )
                    case .ongoing:
                        InvestorOngoingDealsView(searchText: searchText)
                    case .completed:
                        InvestorCompletedDealsView(searchText: searchText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invest")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: tabRouter.investorInvestSegment) { _, _ in
                // Reset search when switching tabs so each is independent
                searchText = ""
                exploreType = nil
                exploreFundingBracket = .any
                exploreSort = .newest
            }
        }
    }

    private var searchPrompt: String {
        switch tabRouter.investorInvestSegment {
        case .myRequests: return "Search requests"
        case .explore:    return "Search title, category, location"
        case .ongoing:    return "Search ongoing deals"
        case .completed:  return "Search completed deals"
        }
    }

    @ViewBuilder
    private var filterMenuContent: some View {
        if hasActiveConstraints {
            Button("Reset filters", role: .destructive) {
                searchText = ""
                exploreType = nil
                exploreFundingBracket = .any
                exploreSort = .newest
            }
        }
        if tabRouter.investorInvestSegment == .explore {
            Section("Sort") {
                Picker("Sort", selection: $exploreSort) {
                    ForEach(MarketExploreSort.allCases, id: \.self) { s in
                        Text(s.title).tag(s)
                    }
                }
            }
            Section("Investment type") {
                Picker("Type", selection: $exploreType) {
                    Text("All types").tag(Optional<InvestmentType>.none)
                    ForEach(InvestmentType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(Optional(t))
                    }
                }
            }
            Section("Funding goal") {
                Picker("Funding goal", selection: $exploreFundingBracket) {
                    ForEach(OpportunityFundingBracket.allCases) { b in
                        Text(b.menuTitle).tag(b)
                    }
                }
            }
        }
    }
}

#Preview {
    InvestorActionTabView()
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
}
