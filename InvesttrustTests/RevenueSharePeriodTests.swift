import FirebaseCore
import FirebaseFirestore
import XCTest
@testable import Investtrust

// Tests for equity revenue-share periods — the recurring payment windows shown
// on the equity deal screen where the seeker declares revenue and pays the investor's share.
final class RevenueSharePeriodTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // Firebase must be initialised so Timestamp fields can be constructed
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(
                googleAppID: "1:000000000000:ios:0000000000000000000000",
                gcmSenderID: "000000000000"
            )
            options.projectID = "investtrust-unit-tests"
            options.apiKey = "unit-test"
            FirebaseApp.configure(options: options)
        }
    }

    func testGeneratorBuildsExpectedPeriodCount() {
        // Generating 4 periods should produce 4 rows, numbered 1–4, all awaiting declaration
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let rows = RevenueShareScheduleGenerator.generatePeriods(startDate: start, periodCount: 4)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.first?.periodNo, 1)
        XCTAssertEqual(rows.last?.periodNo, 4)
        XCTAssertTrue(rows.allSatisfy { $0.status == .awaiting_declaration })
    }

    func testFirestoreRoundTripKeepsSplitProofArrays() {
        // A confirmed period saved to Firestore and read back should keep seeker and investor proofs separate
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
        // Old documents only had a combined proofImageURLs; those should be attributed to the seeker
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
