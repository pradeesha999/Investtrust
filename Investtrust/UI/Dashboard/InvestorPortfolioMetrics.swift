import Foundation

/// Portfolio math and projections for the investor dashboard. Labels favor honesty (“Expected”, “Projected”).
enum InvestorPortfolioMetrics {

    struct UpcomingPayment: Identifiable, Equatable {
        let date: Date
        let amount: Double
        let title: String
        let isProjected: Bool
        var id: String { "\(title)-\(date.timeIntervalSince1970)" }
    }

    struct ChartPoint: Identifiable, Equatable {
        let periodEnd: Date
        let cumulativeInvested: Double
        let cumulativeReturned: Double
        var id: Date { periodEnd }
    }

    enum DashboardPhase {
        case newUser
        case pendingOnly
        case active
        case completedHeavy
    }

    // MARK: - Portfolio summary

    /// Principal in deals with a fully signed MOA (`agreementStatus == active`).
    static func totalInvestedInBook(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            guard r.agreementStatus == .active else { return sum }
            return sum + r.investmentAmount
        }
    }

    static func totalPendingAmount(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            r.status.lowercased() == "pending" ? sum + r.investmentAmount : sum
        }
    }

    /// Simple maturity-style total (projected — label in UI). Only counts fully signed agreements.
    static func expectedReturnTotal(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            guard r.agreementStatus == .active else { return sum }
            return sum + projectedMaturityValue(for: r)
        }
    }

    static func receivedTotal(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { $0 + $1.receivedAmount }
    }

    static func activeDealsCount(_ rows: [InvestmentListing]) -> Int {
        rows.filter { $0.agreementStatus == .active }.count
    }

    static func completedDealsCount(_ rows: [InvestmentListing]) -> Int {
        rows.filter { $0.status.lowercased() == "completed" }.count
    }

    static func phase(rows: [InvestmentListing]) -> DashboardPhase {
        if rows.isEmpty { return .newUser }
        let hasActive = rows.contains { $0.agreementStatus == .active }
        if hasActive { return .active }
        let onlyPending = rows.allSatisfy { $0.status.lowercased() == "pending" }
        if onlyPending { return .pendingOnly }
        let completed = completedDealsCount(rows)
        if completed >= rows.count / 2, rows.count >= 2 { return .completedHeavy }
        return .active
    }

    // MARK: - Progress 0...1

    static func progress01(for row: InvestmentListing) -> Double {
        let s = row.status.lowercased()
        if s == "pending" { return 0.08 }
        if row.agreementStatus == .pending_signatures { return 0.25 }
        if s == "declined" || s == "rejected" { return 0 }
        if s == "completed" { return 1 }
        guard row.agreementStatus == .active else {
            if s == "accepted" || s == "active" { return 0.35 }
            return 0
        }

        switch row.investmentType {
        case .loan:
            return loanProgress(row)
        case .revenue_share:
            return revenueShareProgress(row)
        case .project:
            return projectProgress(row)
        case .equity, .custom:
            return 0.45
        }
    }

    private static func loanProgress(_ row: InvestmentListing) -> Double {
        guard let start = row.acceptedAt ?? row.createdAt,
              let months = row.finalTimelineMonths, months > 0 else { return 0.35 }
        let end = Calendar.current.date(byAdding: .month, value: months, to: start) ?? start
        let total = max(end.timeIntervalSince(start), 1)
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    private static func revenueShareProgress(_ row: InvestmentListing) -> Double {
        let target = max(row.investmentAmount * 1.25, 1)
        return min(1, max(0, row.receivedAmount / target))
    }

    private static func projectProgress(_ row: InvestmentListing) -> Double {
        loanProgress(row)
    }

    // MARK: - Upcoming (projected for loans)

    static func upcomingPayments(withinDays: Int = 120, rows: [InvestmentListing]) -> [UpcomingPayment] {
        var out: [UpcomingPayment] = []
        let horizon = Calendar.current.date(byAdding: .day, value: withinDays, to: Date()) ?? Date()

        for r in rows {
            guard r.agreementStatus == .active else { continue }

            switch r.investmentType {
            case .loan:
                out.append(contentsOf: loanSchedule(r, horizon: horizon))
            case .revenue_share:
                if let p = revenueShareNext(r, horizon: horizon) {
                    out.append(p)
                }
            default:
                break
            }
        }

        return out.sorted { $0.date < $1.date }
    }

    private static func loanSchedule(_ r: InvestmentListing, horizon: Date) -> [UpcomingPayment] {
        guard let start = r.acceptedAt ?? r.createdAt,
              let months = r.finalTimelineMonths, months > 0 else { return [] }
        let principal = r.investmentAmount
        let totalDue = projectedMaturityValue(for: r)
        let interestPortion = max(0, totalDue - principal)
        let monthly = interestPortion / Double(max(months, 1)) + principal / Double(max(months, 1))

        var payments: [UpcomingPayment] = []
        for i in 1...months {
            guard let due = Calendar.current.date(byAdding: .month, value: i, to: start),
                  due <= horizon, due >= Date().addingTimeInterval(-86400) else { continue }
            payments.append(
                UpcomingPayment(
                    date: due,
                    amount: monthly,
                    title: r.opportunityTitle.isEmpty ? "Loan repayment" : r.opportunityTitle,
                    isProjected: true
                )
            )
        }
        return Array(payments.prefix(6))
    }

    private static func revenueShareNext(_ r: InvestmentListing, horizon: Date) -> UpcomingPayment? {
        guard let start = r.acceptedAt ?? r.createdAt else { return nil }
        guard let next = Calendar.current.date(byAdding: .month, value: 1, to: start), next <= horizon else { return nil }
        let guess = max(r.investmentAmount * 0.05, 1)
        return UpcomingPayment(
            date: max(next, Date()),
            amount: guess,
            title: r.opportunityTitle.isEmpty ? "Revenue share" : r.opportunityTitle,
            isProjected: true
        )
    }

    // MARK: - Chart

    static func chartPoints(monthsBack: Int = 6, rows: [InvestmentListing]) -> [ChartPoint] {
        let cal = Calendar.current
        let now = Date()
        var points: [ChartPoint] = []

        for back in (0..<monthsBack).reversed() {
            guard let monthEnd = cal.date(byAdding: .month, value: -back, to: now) else { continue }
            let invested = rows.reduce(0.0) { sum, r in
                let t = r.createdAt ?? now
                guard t <= monthEnd else { return sum }
                let s = r.status.lowercased()
                if ["declined", "rejected", "cancelled", "withdrawn"].contains(s) { return sum }
                guard r.agreementStatus == .active else { return sum }
                return sum + r.investmentAmount
            }
            let returned = rows.reduce(0.0) { sum, r in
                guard (r.createdAt ?? now) <= monthEnd else { return sum }
                return sum + r.receivedAmount
            }
            points.append(ChartPoint(periodEnd: monthEnd, cumulativeInvested: invested, cumulativeReturned: returned))
        }
        return points
    }

    // MARK: - Helpers

    static func projectedMaturityValue(for r: InvestmentListing) -> Double {
        let p = r.investmentAmount
        guard let months = r.finalTimelineMonths, months > 0 else { return p }
        let rate = r.finalInterestRate ?? 0
        let years = Double(months) / 12
        return p + p * (rate / 100) * years
    }

    static func displayStatus(for row: InvestmentListing) -> String {
        row.lifecycleDisplayTitle
    }
}
