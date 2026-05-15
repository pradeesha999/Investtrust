import Foundation

// Financial preview helpers used in the Create Opportunity wizard and on the investor's key-numbers tile.
// Calculates total repayable, installment dates, and equity slice without needing live Firestore data.
enum OpportunityFinancialPreview {
    // Formats a number as a whole-number LKR amount (e.g. 1,500,000) — no decimal places shown
    static func formatLKRInteger(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let n = NSNumber(value: rounded)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", rounded)
    }

    nonisolated static func mediumDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    // Converts the wizard's timeline field to months for interest and schedule calculations
    // (weekly input is in weeks; must be rounded up to months before calling LoanScheduleGenerator)
    static func loanTermMonthsFromWizardInput(rawTimeline: Int, repaymentFrequency: RepaymentFrequency) -> Int {
        switch repaymentFrequency {
        case .weekly:
            max(1, Int(ceil(Double(rawTimeline) / LoanScheduleGenerator.weeksPerMonth)))
        case .monthly, .one_time:
            max(1, rawTimeline)
        }
    }

    // Summary of the financial outcome shown on the investor's key-numbers tile
    struct LoanMoneyOutcome: Equatable {
        let termMonthsForInterest: Int
        let totalRepayable: Double
        let interestAmount: Double
        let firstInstallmentDue: Date?
        let maturityDue: Date?
    }

    // Calculates total repayable, interest earned, and the first/last installment dates for a loan deal
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

    // Calculates the investor’s equity slice if the full round fills at their ticket size
    static func equitySlicePercent(roundEquityPercent: Double, investorAmount: Double, goalAmount: Double) -> Double? {
        guard goalAmount > 0, investorAmount > 0, roundEquityPercent > 0 else { return nil }
        return roundEquityPercent * (investorAmount / goalAmount)
    }
}
