import SwiftUI

struct DashboardView: View {
    @Environment(AuthService.self) private var auth
    
    @State private var opportunities: [OpportunityListing] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedOpportunity: OpportunityListing?
    
    private let opportunityService = OpportunityService()
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    modeToggle
                    marketHeader
                    
                    if isLoading && opportunities.isEmpty {
                        ProgressView("Loading opportunities…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    } else if let loadError {
                        errorState(loadError)
                    } else if opportunities.isEmpty {
                        emptyState
                    } else {
                        opportunityCards
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .navigationDestination(item: $selectedOpportunity) { opp in
                OpportunityDetailView(opportunity: opp)
            }
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
            Text("Browse opportunities and track your investments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var displayNameText: String {
        auth.currentUserEmail ?? "Investor"
    }
    
    private var modeToggle: some View {
        HStack(spacing: 8) {
            Text("Mode")
                .font(.subheadline.weight(.semibold))
            
            Spacer()
            
            Text(auth.activeProfile == .investor ? "Investor" : "Opportunity Seeker")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.06), in: Capsule())
        }
    }
    
    private var marketHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Opportunities")
                    .font(.headline)
                Spacer()
            }
            Text("Open listings from seekers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }
    
    private var opportunityCards: some View {
        LazyVStack(spacing: 14) {
            ForEach(opportunities) { opp in
                OpportunityCard(opp: opp) {
                    selectedOpportunity = opp
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No open opportunities yet")
                .font(.headline)
            Text("When seekers publish investment opportunities, they will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't load opportunities")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AuthTheme.primaryPink)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
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

private struct OpportunityCard: View {
    let opp: OpportunityListing
    var onViewTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StorageBackedAsyncImage(
                reference: opp.imageStoragePaths.first,
                height: 190,
                cornerRadius: 16
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(opp.title)
                    .font(.headline)
                    .lineLimit(2)
                if !opp.category.isEmpty {
                    Text(opp.category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("LKR \(opp.formattedAmountLKR)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(opp.interestRate)%")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timeline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(opp.repaymentLabel)
                        .font(.subheadline.weight(.semibold))
                }
            }
            
            if !opp.description.isEmpty {
                Text(opp.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Button {
                onViewTapped()
            } label: {
                Text("View more")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(AuthTheme.primaryPink, in: Capsule())
            .foregroundStyle(.white)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

#Preview {
    DashboardView()
        .environment(AuthService.previewSignedIn)
}
