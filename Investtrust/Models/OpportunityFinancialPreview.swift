import Foundation

/// Shared simple-interest / schedule math for opportunity UIs (`LoanScheduleGenerator`).
enum OpportunityFinancialPreview {
    static func formatLKRInteger(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let n = NSNumber(value: rounded)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", rounded)
    }

    static func mediumDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }

    /// Wizard timeline field: months (or weeks when frequency is weekly) → months used for interest math.
    static func loanTermMonthsFromWizardInput(rawTimeline: Int, repaymentFrequency: RepaymentFrequency) -> Int {
        switch repaymentFrequency {
        case .weekly:
            // Round up so weekly input is never shortened when converted to month-based interest/schedule math.
            max(1, Int(ceil(Double(rawTimeline) / LoanScheduleGenerator.weeksPerMonth)))
        case .monthly, .one_time:
            max(1, rawTimeline)
        }
    }

    struct LoanMoneyOutcome: Equatable {
        let termMonthsForInterest: Int
        let totalRepayable: Double
        let interestAmount: Double
        let firstInstallmentDue: Date?
        let maturityDue: Date?
    }

    static func loanMoneyOutcome(
        principal: Double,
        annualRatePercent: Double,
        termMonths: Int,
        plan: LoanRepaymentPlan,
        scheduleStart: Date = Date()
    ) -> LoanMoneyOutcome? {
        guard principal > 0, termMonths > 0 else { return nil }
        let total = LoanScheduleGenerator.totalRepayable(
            principal: principal,
            annualRatePercent: annualRatePercent,
            termMonths: termMonths
        )
        let rows = LoanScheduleGenerator.generateSchedule(
            principal: principal,
            annualRatePercent: annualRatePercent,
            termMonths: termMonths,
            plan: plan,
            startDate: scheduleStart
        )
        guard !rows.isEmpty else { return nil }
        return LoanMoneyOutcome(
            termMonthsForInterest: termMonths,
            totalRepayable: total,
            interestAmount: max(0, total - principal),
            firstInstallmentDue: rows.first?.dueDate,
            maturityDue: rows.last?.dueDate
        )
    }

    /// Pro‑rata slice of the round’s equity % when the round fills (`equityOffered * (ticket / goal)`).
    static func equitySlicePercent(roundEquityPercent: Double, investorAmount: Double, goalAmount: Double) -> Double? {
        guard goalAmount > 0, investorAmount > 0, roundEquityPercent > 0 else { return nil }
        return roundEquityPercent * (investorAmount / goalAmount)
    }
}
