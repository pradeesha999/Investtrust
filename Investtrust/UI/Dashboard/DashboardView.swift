import SwiftUI

struct DashboardView: View {
    @Environment(AuthService.self) private var auth

    @State private var opportunities: [OpportunityListing] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let opportunityService = OpportunityService()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                    headerSection
                    profileHintCard
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
                        opportunityCards
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Opportunities")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hi,")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(displayNameText)
                .font(.title.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text("Browse opportunities and track your investments from the Invest tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var displayNameText: String {
        auth.currentUserEmail ?? "Investor"
    }

    /// Explains active profile and points users to Settings (read-only badge was misleading).
    private var profileHintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active profile")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 10) {
                Text(auth.activeProfile == .investor ? "Investor" : "Opportunity Seeker")
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
                NavigationLink {
                    SettingsContentView()
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text("Change in Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
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

    private var opportunityCards: some View {
        LazyVStack(spacing: AppTheme.stackSpacing) {
            ForEach(opportunities, id: \.id) { opp in
                OpportunityCard(opp: opp)
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
    DashboardView()
        .environment(AuthService.previewSignedIn)
}
