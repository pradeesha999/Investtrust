import SwiftUI

// "Ongoing" segment — shows live deals where the MOA is signed and repayments are in progress
struct InvestorOngoingDealsView: View {
    var searchText: String = ""

    @Environment(AuthService.self) private var auth

    @State private var investments: [InvestmentListing] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let investmentService = InvestmentService()

    private var ongoingInvestments: [InvestmentListing] {
        let rows = investments.filter { InvestorPortfolioMetrics.isOngoingDeal($0) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.opportunityTitle.lowercased().contains(query) }
    }

    private var totalAmountToBeReceived: Double {
        ongoingInvestments.reduce(0) { partial, inv in
            partial + remainingAmountToReceive(for: inv)
        }
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
                            ? "Live investments in progress appear here."
                            : "Try a different search term."
                    )
                } else {
                    receivableHeaderCard
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
        .task { await load() }
        .refreshable { await load() }
    }

    private var receivableHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Amount to be received")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("LKR \(formatAmount(totalAmountToBeReceived))")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(auth.accentColor)
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

    private func remainingAmountToReceive(for inv: InvestmentListing) -> Double {
        if !inv.loanInstallments.isEmpty {
            return inv.loanInstallments
                .filter { $0.status != .confirmed_paid }
                .reduce(0) { $0 + $1.totalDue }
        }
        if !inv.revenueSharePeriods.isEmpty {
            return inv.revenueSharePeriods
                .filter { $0.status != .confirmed_paid }
                .reduce(0) { partial, period in
                    partial + max(0, period.expectedShareAmount ?? period.actualPaidAmount ?? 0)
                }
        }
        return 0
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
        InvestorOngoingDealsView()
    }
    .environment(AuthService.previewSignedIn)
}
