import SwiftUI

struct InvestorMarketView: View {
    @Environment(AuthService.self) private var auth

    @State private var investments: [InvestmentListing] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""

    private let investmentService = InvestmentService()

    var filteredInvestments: [InvestmentListing] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return investments
        }
        let q = searchText.lowercased()
        return investments.filter { $0.opportunityTitle.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.stackSpacing) {
                if isLoading && investments.isEmpty {
                    ProgressView("Loading requests…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if let loadError {
                    StatusBlock(
                        icon: "exclamationmark.triangle.fill",
                        title: "Couldn't load investments",
                        message: loadError,
                        iconColor: .orange,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                } else if filteredInvestments.isEmpty {
                    StatusBlock(
                        icon: "doc.richtext",
                        title: searchText.isEmpty ? "No requests yet" : "No matches",
                        message: searchText.isEmpty
                            ? "Use Explore to find listings, then send a request. Statuses appear here."
                            : "Try a different search term."
                    )
                } else {
                    LazyVStack(spacing: AppTheme.stackSpacing) {
                        ForEach(filteredInvestments) { inv in
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
        InvestorMarketView()
    }
    .environment(AuthService.previewSignedIn)
    .environmentObject(MainTabRouter())
}
