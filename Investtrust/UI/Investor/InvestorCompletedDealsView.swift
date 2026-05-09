import SwiftUI

/// Investor deals that have fully completed repayment and are closed.
struct InvestorCompletedDealsView: View {
    var searchText: String = ""

    @Environment(AuthService.self) private var auth

    @State private var investments: [InvestmentListing] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let investmentService = InvestmentService()

    private var completedInvestments: [InvestmentListing] {
        let rows = InvestorPortfolioMetrics.rowsForCompletedTab(investments)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.opportunityTitle.lowercased().contains(query) }
    }

    private var totalProfitCollected: Double {
        completedInvestments.reduce(0) { total, inv in
            let returned = InvestorPortfolioMetrics.returnedValue(for: inv)
            return total + max(0, returned - inv.effectiveAmount)
        }
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
                    profitHeaderCard
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

    private var profitHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profit collected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("LKR \(formatAmount(totalProfitCollected))")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(auth.accentColor)
            Text("From all completed investments")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
        .appCardShadow()
    }

    private func formatAmount(_ value: Double) -> String {
        let n = NSNumber(value: max(0, value))
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", max(0, value))
    }
}

#Preview {
    NavigationStack {
        InvestorCompletedDealsView()
    }
    .environment(AuthService.previewSignedIn)
}
