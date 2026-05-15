import SwiftUI

// Summary row in a deal card that opens the full loan repayment schedule when tapped
struct LoanInstallmentsSection: View {
    let investment: InvestmentListing
    var currentUserId: String?
    var onRefresh: () async -> Void

    private var sorted: [LoanInstallment] {
        investment.loanInstallments.sorted { $0.installmentNo < $1.installmentNo }
    }

    private var totalCount: Int { sorted.count }

    private var paidCount: Int {
        sorted.filter { $0.status == .confirmed_paid }.count
    }

    private var nextOpen: LoanInstallment? {
        sorted
            .filter { $0.status != .confirmed_paid }
            .min(by: { $0.dueDate < $1.dueDate })
    }

    var body: some View {
        NavigationLink {
            LoanRepaymentScheduleView(
                investment: investment,
                currentUserId: currentUserId,
                onRefresh: onRefresh
            )
            .id(investment.loanScheduleStateId)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: "calendar.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Loan repayments")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let next = nextOpen {
                        Text("Next \(shortDate(next.dueDate)) · LKR \(formatAmt(next.totalDue))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if paidCount == totalCount, totalCount > 0 {
                        Text("Loan complete · open for full payment history")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All \(totalCount) installments done")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.cardPadding)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(Color.blue.opacity(0.22), lineWidth: 1)
            )
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

private extension InvestmentListing {
    // Bumps `NavigationLink` identity when installment rows change so the schedule screen picks up fresh data after refresh.
    var loanScheduleStateId: String {
        let parts = loanInstallments
            .sorted { $0.installmentNo < $1.installmentNo }
            .map { "\($0.installmentNo):\($0.status.rawValue):\($0.seekerProofImageURLs.count):\($0.investorProofImageURLs.count)" }
        return id + "|" + parts.joined(separator: ",")
            + "|ps:\(principalSentByInvestorAt?.timeIntervalSince1970 ?? 0)"
            + "|snr:\(principalSeekerNotReceivedAt?.timeIntervalSince1970 ?? 0)"
            + "|pic:\(principalInvestorProofImageURLs.count)"
    }
}
