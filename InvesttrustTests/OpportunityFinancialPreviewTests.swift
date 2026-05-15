import XCTest
@testable import Investtrust

// Tests for the financial preview numbers shown during opportunity creation
// and on the investor's key-numbers tile (total repayable, installment dates, equity slice).
final class OpportunityFinancialPreviewTests: XCTestCase {

    func testFormatLKRInteger_roundsAndStripsDecimals() {
        // Amounts shown in the app should never display a decimal point
        let formatted = OpportunityFinancialPreview.formatLKRInteger(1_234_567.89)
        XCTAssertFalse(formatted.contains("."), "Formatter should produce an integer with no fractional part")
        XCTAssertFalse(formatted.isEmpty)
    }

    func testLoanTermMonthsFromWizardInput_weeklyRoundsUpToMonths() {
        // When the seeker picks weekly repayment in the wizard, the weekly count is converted to months (ceiling)
        // 5 weeks → ceil(5 / 4.345) → 2 months
        XCTAssertEqual(
            OpportunityFinancialPreview.loanTermMonthsFromWizardInput(rawTimeline: 5, repaymentFrequency: .weekly),
            2
        )
        // 1 week → 1 month minimum
        XCTAssertEqual(
            OpportunityFinancialPreview.loanTermMonthsFromWizardInput(rawTimeline: 1, repaymentFrequency: .weekly),
            1
        )
    }

    func testLoanTermMonthsFromWizardInput_monthlyAndOneTimePassThrough() {
        // Monthly and one-time inputs are used as-is; zero collapses to 1 so the schedule is never empty
        XCTAssertEqual(
            OpportunityFinancialPreview.loanTermMonthsFromWizardInput(rawTimeline: 12, repaymentFrequency: .monthly),
            12
        )
        XCTAssertEqual(
            OpportunityFinancialPreview.loanTermMonthsFromWizardInput(rawTimeline: 36, repaymentFrequency: .one_time),
            36
        )
        XCTAssertEqual(
            OpportunityFinancialPreview.loanTermMonthsFromWizardInput(rawTimeline: 0, repaymentFrequency: .monthly),
            1,
            "Wizard input must never collapse to 0 months"
        )
    }

    func testLoanMoneyOutcome_nilForZeroPrincipal() {
        // The preview tile should not render if the principal or term is 0
        XCTAssertNil(OpportunityFinancialPreview.loanMoneyOutcome(
            principal: 0,
            annualRatePercent: 12,
            termMonths: 12,
            plan: .monthly
        ))
        XCTAssertNil(OpportunityFinancialPreview.loanMoneyOutcome(
            principal: 100_000,
            annualRatePercent: 12,
            termMonths: 0,
            plan: .monthly
        ))
    }

    func testLoanMoneyOutcome_returnsConsistentTotalsAndDates() throws {
        // LKR 100,000 at 12% for 12 months → LKR 112,000 total, LKR 12,000 interest
        let outcome = OpportunityFinancialPreview.loanMoneyOutcome(
            principal: 100_000,
            annualRatePercent: 12,
            termMonths: 12,
            plan: .monthly,
            scheduleStart: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let resolved = try XCTUnwrap(outcome)
        XCTAssertEqual(resolved.termMonthsForInterest, 12)
        XCTAssertEqual(resolved.totalRepayable, 112_000, accuracy: 0.01)
        XCTAssertEqual(resolved.interestAmount, 12_000, accuracy: 0.01)
        // First payment must be before the final payment
        let first = try XCTUnwrap(resolved.firstInstallmentDue)
        let last = try XCTUnwrap(resolved.maturityDue)
        XCTAssertLessThanOrEqual(first, last)
    }

    func testEquitySlicePercent_proportionalToTicketShare() throws {
        // An investor taking half the round at 10% equity should receive 5% of the company
        let slice = try XCTUnwrap(
            OpportunityFinancialPreview.equitySlicePercent(
                roundEquityPercent: 10,
                investorAmount: 500_000,
                goalAmount: 1_000_000
            )
        )
        XCTAssertEqual(slice, 5, accuracy: 0.0001)
    }

    func testEquitySlicePercent_nilForInvalidInputs() {
        // If the investor amount, goal, or equity % is zero, no slice can be calculated
        XCTAssertNil(OpportunityFinancialPreview.equitySlicePercent(roundEquityPercent: 10, investorAmount: 0, goalAmount: 1_000_000))
        XCTAssertNil(OpportunityFinancialPreview.equitySlicePercent(roundEquityPercent: 10, investorAmount: 100_000, goalAmount: 0))
        XCTAssertNil(OpportunityFinancialPreview.equitySlicePercent(roundEquityPercent: 0, investorAmount: 100_000, goalAmount: 1_000_000))
    }
}
