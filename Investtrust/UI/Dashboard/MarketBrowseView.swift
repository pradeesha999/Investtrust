import SwiftUI

/// Open market listings (browse) — not the investor portfolio dashboard.
struct MarketBrowseView: View {
    @Environment(AuthService.self) private var auth

    @State private var opportunities: [OpportunityListing] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let opportunityService = OpportunityService()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                marketHeader

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
                        message: "When seekers publish investment opportunities, they will appear here."
                    )
                } else {
                    LazyVStack(spacing: AppTheme.stackSpacing) {
                        ForEach(opportunities, id: \.id) { opp in
                            OpportunityCard(opp: opp)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var marketHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Open listings")
                    .font(.headline)
                Spacer()
            }
            Text("From other seekers on the market")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await opportunityService.fetchMarketListings()
            if let userID = auth.currentUserID {
                opportunities = all.filter { $0.ownerId != userID }
            } else {
                opportunities = all
            }
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        MarketBrowseView()
            .environment(AuthService.previewSignedIn)
    }
}
