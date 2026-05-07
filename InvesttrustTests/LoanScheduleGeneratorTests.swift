import XCTest
@testable import Investtrust
import FirebaseFirestore

final class LoanScheduleGeneratorTests: XCTestCase {
    func testTotalRepayable_simpleInterest() {
        let total = LoanScheduleGenerator.totalRepayable(principal: 10_000, annualRatePercent: 12, termMonths: 12)
        XCTAssertEqual(total, 11_200, accuracy: 0.01)
    }

    func testMonthlyInstallmentsSumMatchesTotal() {
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
        let parts = LoanScheduleGenerator.equalParts(total: 10.0, count: 3)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.reduce(0, +), 10.0, accuracy: 0.001)
    }
}

final class InappropriateImageGateTests: XCTestCase {
    func testGateErrorCopy() {
        let e = InappropriateImageGate.GateError.inappropriateContent
        XCTAssertFalse((e as LocalizedError).errorDescription?.isEmpty ?? true)
    }
}

final class LoanInstallmentFirestoreMappingTests: XCTestCase {
    func testFirestoreInit_legacyProofArrayFallsBackToSeekerProofs() {
        let due = Date(timeIntervalSince1970: 1_710_000_000)
        let paidAt = Date(timeIntervalSince1970: 1_710_100_000)
        let receivedAt = Date(timeIntervalSince1970: 1_710_200_000)

        let map: [String: Any] = [
            "installmentNo": 3,
            "dueDate": Timestamp(date: due),
            "principalComponent": 7_500.0,
            "interestComponent": 500.0,
            "totalDue": 8_000.0,
            "status": "awaiting_confirmation",
            "investorMarkedPaidAt": Timestamp(date: paidAt),
            "seekerMarkedReceivedAt": Timestamp(date: receivedAt),
            "proofImageURLs": [
                "https://example.com/slip-1.jpg",
                "https://example.com/slip-2.jpg",
            ],
        ]

        let row = LoanInstallment(firestoreMap: map)
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.seekerProofImageURLs.count, 2)
        XCTAssertEqual(row?.investorProofImageURLs.count, 0)
        XCTAssertEqual(row?.proofImageURLs.count, 2)
    }

    func testFirestoreInit_splitProofArraysPreferredOverLegacy() {
        let due = Date(timeIntervalSince1970: 1_710_000_000)
        let map: [String: Any] = [
            "installmentNo": 1,
            "dueDate": Timestamp(date: due),
            "principalComponent": 1_000.0,
            "interestComponent": 100.0,
            "totalDue": 1_100.0,
            "status": "scheduled",
            "proofImageURLs": ["https://example.com/legacy.jpg"],
            "seekerProofImageURLs": ["https://example.com/seeker.jpg"],
            "investorProofImageURLs": ["https://example.com/investor.jpg"],
        ]

        let row = LoanInstallment(firestoreMap: map)
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.seekerProofImageURLs, ["https://example.com/seeker.jpg"])
        XCTAssertEqual(row?.investorProofImageURLs, ["https://example.com/investor.jpg"])
        XCTAssertEqual(row?.proofImageURLs, ["https://example.com/seeker.jpg", "https://example.com/investor.jpg"])
    }

    func testFirestoreMap_writesSplitAndCombinedProofFields() {
        let due = Date(timeIntervalSince1970: 1_710_000_000)
        let sentAt = Date(timeIntervalSince1970: 1_710_300_000)
        let receivedAt = Date(timeIntervalSince1970: 1_710_350_000)
        let row = LoanInstallment(
            installmentNo: 2,
            dueDate: due,
            principalComponent: 2_000.0,
            interestComponent: 120.0,
            totalDue: 2_120.0,
            status: .confirmed_paid,
            investorMarkedPaidAt: receivedAt,
            seekerMarkedReceivedAt: sentAt,
            seekerProofImageURLs: ["https://example.com/s1.jpg"],
            investorProofImageURLs: ["https://example.com/i1.jpg", "https://example.com/i2.jpg"]
        )

        let map = row.firestoreMap()
        XCTAssertEqual(map["seekerProofImageURLs"] as? [String], ["https://example.com/s1.jpg"])
        XCTAssertEqual(map["investorProofImageURLs"] as? [String], ["https://example.com/i1.jpg", "https://example.com/i2.jpg"])
        XCTAssertEqual(
            map["proofImageURLs"] as? [String],
            ["https://example.com/s1.jpg", "https://example.com/i1.jpg", "https://example.com/i2.jpg"]
        )
        XCTAssertNotNil(map["investorMarkedPaidAt"] as? Timestamp)
        XCTAssertNotNil(map["seekerMarkedReceivedAt"] as? Timestamp)
    }

    func testCombinedProofProperty_ordersSeekerThenInvestor() {
        let row = LoanInstallment(
            installmentNo: 4,
            dueDate: Date(timeIntervalSince1970: 1_710_000_000),
            principalComponent: 3_000.0,
            interestComponent: 300.0,
            totalDue: 3_300.0,
            status: .awaiting_confirmation,
            investorMarkedPaidAt: nil,
            seekerMarkedReceivedAt: nil,
            seekerProofImageURLs: ["sA", "sB"],
            investorProofImageURLs: ["iA"]
        )

        XCTAssertEqual(row.proofImageURLs, ["sA", "sB", "iA"])
    }
}

final class RevenueSharePeriodModelTests: XCTestCase {
    func testGeneratorBuildsExpectedPeriodCount() {
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let rows = RevenueShareScheduleGenerator.generatePeriods(startDate: start, periodCount: 4)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.first?.periodNo, 1)
        XCTAssertEqual(rows.last?.periodNo, 4)
        XCTAssertTrue(rows.allSatisfy { $0.status == .awaiting_declaration })
    }

    func testFirestoreRoundTripKeepsSplitProofArrays() {
        let row = RevenueSharePeriod(
            periodNo: 2,
            startDate: Date(timeIntervalSince1970: 1_710_000_000),
            endDate: Date(timeIntervalSince1970: 1_712_000_000),
            dueDate: Date(timeIntervalSince1970: 1_712_000_000),
            declaredRevenue: 250_000,
            expectedShareAmount: 20_000,
            actualPaidAmount: 20_000,
            seekerDeclaredAt: Date(timeIntervalSince1970: 1_711_000_000),
            seekerMarkedSentAt: Date(timeIntervalSince1970: 1_711_100_000),
            investorMarkedReceivedAt: Date(timeIntervalSince1970: 1_711_200_000),
            status: .confirmed_paid,
            seekerProofImageURLs: ["s-1"],
            investorProofImageURLs: ["i-1", "i-2"]
        )
        let map = row.firestoreMap()
        let decoded = RevenueSharePeriod(firestoreMap: map)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.seekerProofImageURLs, ["s-1"])
        XCTAssertEqual(decoded?.investorProofImageURLs, ["i-1", "i-2"])
        XCTAssertEqual(decoded?.proofImageURLs, ["s-1", "i-1", "i-2"])
    }

    func testFirestoreInitFallsBackToLegacyProofArray() {
        let map: [String: Any] = [
            "periodNo": 1,
            "startDate": Timestamp(date: Date(timeIntervalSince1970: 1_710_000_000)),
            "endDate": Timestamp(date: Date(timeIntervalSince1970: 1_712_000_000)),
            "dueDate": Timestamp(date: Date(timeIntervalSince1970: 1_712_000_000)),
            "status": RevenueSharePeriodStatus.awaiting_confirmation.rawValue,
            "proofImageURLs": ["legacy-a", "legacy-b"]
        ]
        let decoded = RevenueSharePeriod(firestoreMap: map)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.seekerProofImageURLs, ["legacy-a", "legacy-b"])
        XCTAssertEqual(decoded?.investorProofImageURLs, [])
    }
}
