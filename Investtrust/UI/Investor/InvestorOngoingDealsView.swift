import SwiftUI

/// Investor deals that are fully signed and live.
struct InvestorOngoingDealsView: View {
    @Environment(AuthService.self) private var auth

    @State private var investments: [InvestmentListing] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""

    private let investmentService = InvestmentService()

    private var ongoingInvestments: [InvestmentListing] {
        let rows = investments.filter { inv in
            inv.agreementStatus == .active || inv.status.lowercased() == "active" || inv.status.lowercased() == "completed"
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.opportunityTitle.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.stackSpacing) {
                if isLoading && investments.isEmpty {
                    ProgressView("Loading ongoing deals…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if let loadError {
                    StatusBlock(
                        icon: "exclamationmark.triangle.fill",
                        title: "Couldn't load ongoing deals",
                        message: loadError,
                        iconColor: .orange,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                } else if ongoingInvestments.isEmpty {
                    StatusBlock(
                        icon: "checkmark.seal",
                        title: searchText.isEmpty ? "No ongoing deals yet" : "No matches",
                        message: searchText.isEmpty
                            ? "Deals appear here after all signatures are completed and agreements are active."
                            : "Try a different search term."
                    )
                } else {
                    LazyVStack(spacing: AppTheme.stackSpacing) {
                        ForEach(ongoingInvestments) { inv in
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
        InvestorOngoingDealsView()
    }
    .environment(AuthService.previewSignedIn)
}
