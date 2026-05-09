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

    static func isCompletedDeal(_ row: InvestmentListing) -> Bool {
        let s = row.status.lowercased()
        if s == "completed" || row.fundingStatus == .closed {
            return true
        }
        if row.investmentType == .equity,
           !row.equityMilestones.isEmpty,
           row.equityMilestones.allSatisfy({ $0.status == .completed }) {
            return true
        }
        return false
    }

    static func isOngoingDeal(_ row: InvestmentListing) -> Bool {
        if isCompletedDeal(row) { return false }
        let s = row.status.lowercased()
        if ["declined", "rejected", "cancelled", "withdrawn"].contains(s) {
            return false
        }
        if row.agreementStatus == .active || row.agreementStatus == .pending_signatures {
            return true
        }
        return s == "accepted" || s == "active"
    }

    /// Principal in deals with a fully signed MOA (`agreementStatus == active`).
    static func totalInvestedInBook(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            guard isOngoingDeal(r) else { return sum }
            return sum + r.effectiveAmount
        }
    }

    static func totalPendingAmount(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            r.status.lowercased() == "pending" ? sum + r.effectiveAmount : sum
        }
    }

    /// Simple maturity-style total (projected — label in UI). Only counts fully signed agreements.
    static func expectedReturnTotal(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            guard isOngoingDeal(r) else { return sum }
            return sum + projectedMaturityValue(for: r)
        }
    }

    static func receivedTotal(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            sum + returnedValue(for: r)
        }
    }

    /// Total amount deployed across all non-pending, non-rejected/cancelled investments.
    static func totalInvestedAllTime(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            let s = r.status.lowercased()
            if ["pending", "declined", "rejected", "cancelled", "withdrawn"].contains(s) {
                return sum
            }
            return sum + r.effectiveAmount
        }
    }

    static func allTimeDealsCount(_ rows: [InvestmentListing]) -> Int {
        rows.filter { r in
            let s = r.status.lowercased()
            return !["pending", "declined", "rejected", "cancelled", "withdrawn"].contains(s)
        }.count
    }

    /// Net position to date from all investments (returned - deployed principal).
    static func pureProfitAllTime(_ rows: [InvestmentListing]) -> Double {
        receivedTotal(rows) - totalInvestedAllTime(rows)
    }

    /// Total projected maturity of currently active deals.
    static func expectedReturnCurrentInvestments(_ rows: [InvestmentListing]) -> Double {
        rows.reduce(0) { sum, r in
            guard isOngoingDeal(r) else { return sum }
            return sum + projectedMaturityValue(for: r)
        }
    }

    /// Repayments counted in portfolio summaries: confirmed loan installments when a schedule exists, else Firestore `receivedAmount`.
    static func returnedValue(for r: InvestmentListing) -> Double {
        if r.isLoanWithSchedule {
            return r.confirmedLoanRepaymentTotal
        }
        return r.receivedAmount
    }

    static func activeDealsCount(_ rows: [InvestmentListing]) -> Int {
        rows.filter { isOngoingDeal($0) }.count
    }

    static func completedDealsCount(_ rows: [InvestmentListing]) -> Int {
        rows.filter { isCompletedDeal($0) }.count
    }

    // MARK: - Investor Invest tab (My requests vs Ongoing)

    /// Rows that belong in **Ongoing** — live MOA / operational deal. Not shown under **My requests**.
    static func isOngoingPortfolioRow(_ inv: InvestmentListing) -> Bool {
        isOngoingDeal(inv)
    }

    static func rowsForCompletedTab(_ rows: [InvestmentListing]) -> [InvestmentListing] {
        rows
            .filter { isCompletedDeal($0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// **My requests** list: pending requests only, one row per opportunity (newest wins).
    static func rowsForMyRequestsTab(_ rows: [InvestmentListing]) -> [InvestmentListing] {
        let pipeline = rows.filter { $0.status.lowercased() == "pending" }
        let byOpp = Dictionary(grouping: pipeline) { inv -> String in
            if let oid = inv.opportunityId, !oid.isEmpty { return oid }
            return inv.id
        }
        let picked = byOpp.values.compactMap { group -> InvestmentListing? in
            group.max { a, b in
                (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
            }
        }
        return picked.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    static func phase(rows: [InvestmentListing]) -> DashboardPhase {
        if rows.isEmpty { return .newUser }
        let hasActive = rows.contains { isOngoingDeal($0) }
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
        guard isOngoingDeal(row) else {
            if s == "accepted" || s == "active" { return 0.35 }
            return 0
        }

        switch row.investmentType {
        case .loan:
            return loanProgress(row)
        case .equity:
            return 0.45
        }
    }

    private static func loanProgress(_ row: InvestmentListing) -> Double {
        if row.isLoanWithSchedule {
            let n = row.loanInstallments.count
            guard n > 0 else { return 0.35 }
            let done = row.loanInstallments.filter { $0.status == .confirmed_paid }.count
            return min(1, max(0, Double(done) / Double(n)))
        }
        guard let start = row.acceptedAt ?? row.createdAt,
              let months = row.effectiveFinalTimelineMonths, months > 0 else { return 0.35 }
        let end = Calendar.current.date(byAdding: .month, value: months, to: start) ?? start
        let total = max(end.timeIntervalSince(start), 1)
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    // MARK: - Upcoming (projected for loans)

    static func upcomingPayments(withinDays: Int = 120, rows: [InvestmentListing]) -> [UpcomingPayment] {
        var out: [UpcomingPayment] = []
        let horizon = Calendar.current.date(byAdding: .day, value: withinDays, to: Date()) ?? Date()

        for r in rows {
            guard isOngoingDeal(r) else { continue }

            switch r.investmentType {
            case .loan:
                out.append(contentsOf: loanSchedule(r, horizon: horizon))
            case .equity:
                break
            }
        }

        return out.sorted { $0.date < $1.date }
    }

    private static func loanSchedule(_ r: InvestmentListing, horizon: Date) -> [UpcomingPayment] {
        if r.isLoanWithSchedule {
            let nowFloor = Date().addingTimeInterval(-86400)
            return r.loanInstallments
                .filter { $0.status != .confirmed_paid }
                .filter { $0.dueDate <= horizon && $0.dueDate >= nowFloor }
                .sorted { $0.dueDate < $1.dueDate }
                .prefix(6)
                .map { inst in
                    UpcomingPayment(
                        date: inst.dueDate,
                        amount: inst.totalDue,
                        title: r.opportunityTitle.isEmpty ? "Loan installment" : r.opportunityTitle,
                        isProjected: false
                    )
                }
        }
        guard let start = r.acceptedAt ?? r.createdAt,
              let months = r.effectiveFinalTimelineMonths, months > 0 else { return [] }
        let principal = r.effectiveAmount
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
        if !r.revenueSharePeriods.isEmpty {
            if let next = r.revenueSharePeriods
                .filter({ $0.status != .confirmed_paid && $0.dueDate <= horizon })
                .sorted(by: { $0.dueDate < $1.dueDate })
                .first {
                let amt = max(0, next.expectedShareAmount ?? 0)
                return UpcomingPayment(
                    date: max(next.dueDate, Date()),
                    amount: amt,
                    title: r.opportunityTitle.isEmpty ? "Revenue share" : r.opportunityTitle,
                    isProjected: true
                )
            }
        }
        guard let start = r.acceptedAt ?? r.createdAt else { return nil }
        guard let next = Calendar.current.date(byAdding: .month, value: 1, to: start), next <= horizon else { return nil }
        let guess = max(r.effectiveAmount * 0.05, 1)
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
                guard isOngoingDeal(r) else { return sum }
                return sum + r.effectiveAmount
            }
            let returned = rows.reduce(0.0) { sum, r in
                guard (r.createdAt ?? now) <= monthEnd else { return sum }
                return sum + returnedValue(for: r)
            }
            points.append(ChartPoint(periodEnd: monthEnd, cumulativeInvested: invested, cumulativeReturned: returned))
        }
        return points
    }

    // MARK: - Helpers

    static func projectedMaturityValue(for r: InvestmentListing) -> Double {
        let p = r.effectiveAmount
        guard let months = r.effectiveFinalTimelineMonths, months > 0 else { return p }
        let rate = r.effectiveFinalInterestRate ?? 0
        let years = Double(months) / 12
        return p + p * (rate / 100) * years
    }

    static func displayStatus(for row: InvestmentListing) -> String {
        row.lifecycleDisplayTitle
    }
}
