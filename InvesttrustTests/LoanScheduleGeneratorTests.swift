import XCTest
@testable import Investtrust

// Tests for loan repayment schedule math (simple interest, equal installments).
// These are the numbers shown on the repayment screen inside an active deal.
final class LoanScheduleGeneratorTests: XCTestCase {

    func testTotalRepayable_simpleInterest() {
        // LKR 10,000 at 12% for 12 months → LKR 11,200 total
        let total = LoanScheduleGenerator.totalRepayable(principal: 10_000, annualRatePercent: 12, termMonths: 12)
        XCTAssertEqual(total, 11_200, accuracy: 0.01)
    }

    func testMonthlyInstallmentsSumMatchesTotal() {
        // All monthly payments must add up to the full repayable amount
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        let principal = 1_000.0
        let rate = 10.0
        let months = 3
        let schedule = LoanScheduleGenerator.generateSchedule(
            principal: principal,
            annualRatePercent: rate,
            termMonths: months,
            plan: .monthly,
            startDate: start,
            calendar: cal
        )
        XCTAssertEqual(schedule.count, months)
        let sum = schedule.reduce(0.0) { $0 + $1.totalDue }
        let expected = LoanScheduleGenerator.totalRepayable(principal: principal, annualRatePercent: rate, termMonths: months)
        XCTAssertEqual(sum, expected, accuracy: 0.02)
    }

    func testWeeklyCountUsesWeeksPerMonth() {
        // Weekly plan: number of rows = term months × weeks-per-month constant
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        let schedule = LoanScheduleGenerator.generateSchedule(
            principal: 5_000,
            annualRatePercent: 8,
            termMonths: 12,
            plan: .weekly,
            startDate: start,
            calendar: cal
        )
        let expectedWeeks = max(1, Int((Double(12) * LoanScheduleGenerator.weeksPerMonth).rounded()))
        XCTAssertEqual(schedule.count, expectedWeeks)
    }

    func testOneTimeProducesSingleRow() {
        // One-time plan: single lump-sum payment at the end of the term
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        let schedule = LoanScheduleGenerator.generateSchedule(
            principal: 2_000,
            annualRatePercent: 6,
            termMonths: 6,
            plan: .one_time,
            startDate: start,
            calendar: cal
        )
        XCTAssertEqual(schedule.count, 1)
        XCTAssertEqual(schedule[0].installmentNo, 1)
        let expected = LoanScheduleGenerator.totalRepayable(principal: 2_000, annualRatePercent: 6, termMonths: 6)
        XCTAssertEqual(schedule[0].totalDue, expected, accuracy: 0.02)
    }

    func testEqualPartsRemainderGoesToLast() {
        // Rounding difference is absorbed by the last installment so totals stay exact
        let parts = LoanScheduleGenerator.equalParts(total: 10.0, count: 3)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.reduce(0, +), 10.0, accuracy: 0.001)
    }

    func testZeroPrincipalOrTermProducesEmptySchedule() {
        // No schedule should be generated if the seeker hasn't filled in the amount or term
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)

        let zeroPrincipal = LoanScheduleGenerator.generateSchedule(
            principal: 0,
            annualRatePercent: 12,
            termMonths: 6,
            plan: .monthly,
            startDate: start,
            calendar: cal
        )
        XCTAssertTrue(zeroPrincipal.isEmpty)

        let zeroTerm = LoanScheduleGenerator.generateSchedule(
            principal: 1_000,
            annualRatePercent: 12,
            termMonths: 0,
            plan: .monthly,
            startDate: start,
            calendar: cal
        )
        XCTAssertTrue(zeroTerm.isEmpty)
    }

    func testMonthlyScheduleDatesIncreaseByOneMonth() {
        // Each payment card on the repayment screen is due exactly one month after the previous
        let cal = Calendar(identifier: .gregorian)
        let components = DateComponents(year: 2024, month: 1, day: 15)
        let start = cal.date(from: components)!

        let schedule = LoanScheduleGenerator.generateSchedule(
            principal: 1_200,
            annualRatePercent: 0,
            termMonths: 3,
            plan: .monthly,
            startDate: start,
            calendar: cal
        )

        XCTAssertEqual(schedule.count, 3)
        for (index, installment) in schedule.enumerated() {
            let expected = cal.date(byAdding: .month, value: index + 1, to: start)!
            XCTAssertEqual(installment.dueDate, expected, "Installment #\(index + 1) due date should be exactly \(index + 1) months after start")
        }
    }
}
