import SwiftUI

struct RevenueSharePeriodsSection: View {
    let investment: InvestmentListing
    var currentUserId: String?
    var onRefresh: () async -> Void

    @Environment(AuthService.self) private var auth

    private var sorted: [RevenueSharePeriod] {
        investment.revenueSharePeriods.sorted { $0.periodNo < $1.periodNo }
    }

    private var paidCount: Int {
        sorted.filter { $0.status == .confirmed_paid }.count
    }

    private var totalCount: Int { sorted.count }

    private var nextOpen: RevenueSharePeriod? {
        sorted.filter { $0.status != .confirmed_paid }.min(by: { $0.dueDate < $1.dueDate })
    }

    var body: some View {
        NavigationLink {
            RevenueShareScheduleView(
                investment: investment,
                currentUserId: currentUserId,
                onRefresh: onRefresh
            )
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                        .fill(auth.accentColor.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.title2)
                        .foregroundStyle(auth.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Revenue share periods")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let nextOpen {
                        let due = nextOpen.expectedShareAmount ?? 0
                        Text("Next: \(shortDate(nextOpen.dueDate)) · Expected LKR \(formatAmt(due))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All \(totalCount) periods complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(paidCount) of \(totalCount) confirmed")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.cardPadding)
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func formatAmt(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }
}
