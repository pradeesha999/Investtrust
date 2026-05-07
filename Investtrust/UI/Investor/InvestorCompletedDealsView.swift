import SwiftUI

/// Investor deals that have fully completed repayment and are closed.
struct InvestorCompletedDealsView: View {
    @Environment(AuthService.self) private var auth

    @State private var investments: [InvestmentListing] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""

    private let investmentService = InvestmentService()

    private var completedInvestments: [InvestmentListing] {
        let rows = InvestorPortfolioMetrics.rowsForCompletedTab(investments)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.opportunityTitle.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.stackSpacing) {
                if isLoading && investments.isEmpty {
                    ProgressView("Loading completed deals…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if let loadError {
                    StatusBlock(
                        icon: "exclamationmark.triangle.fill",
                        title: "Couldn't load completed deals",
                        message: loadError,
                        iconColor: .orange,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                } else if completedInvestments.isEmpty {
                    StatusBlock(
                        icon: "checkmark.seal",
                        title: searchText.isEmpty ? "No completed deals yet" : "No matches",
                        message: searchText.isEmpty
                            ? "Completed investments will appear here."
                            : "Try a different search term."
                    )
                } else {
                    LazyVStack(spacing: AppTheme.stackSpacing) {
                        ForEach(completedInvestments) { inv in
                            InvestmentCard(inv: inv) {
                                await load()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $searchText, prompt: "Search listing")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        guard let userID = auth.currentUserID else {
            loadError = "Please sign in again."
            return
        }
        do {
            investments = try await investmentService.fetchInvestments(forInvestor: userID)
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        InvestorCompletedDealsView()
    }
    .environment(AuthService.previewSignedIn)
}
