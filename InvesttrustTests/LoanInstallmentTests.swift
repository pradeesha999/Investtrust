import FirebaseCore
import FirebaseFirestore
import XCTest
@testable import Investtrust

// Tests for reading and writing a loan installment row in Firestore.
// Each installment appears as a payment card on the seeker's repayment screen.
final class LoanInstallmentTests: XCTestCase {

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

    func testFirestoreInit_legacyProofArrayFallsBackToSeekerProofs() {
        // Old documents used a single proofImageURLs field; these should be attributed to the seeker
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
        // New documents store seeker and investor proof separately; split arrays take priority
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
        // When saving, both the split arrays and the combined list are written to Firestore
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
        // The proof gallery on screen shows seeker slips first, then investor receipts
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

    func testIsFullyConfirmed_requiresBothSidesAcknowledged() {
        // A payment is only fully confirmed when both the investor and the seeker have tapped "Confirm"
        let base = LoanInstallment(
            installmentNo: 1,
            dueDate: Date(timeIntervalSince1970: 1_710_000_000),
            principalComponent: 1_000,
            interestComponent: 100,
            totalDue: 1_100,
            status: .awaiting_confirmation,
            investorMarkedPaidAt: nil,
            seekerMarkedReceivedAt: nil,
            seekerProofImageURLs: [],
            investorProofImageURLs: []
        )

        XCTAssertFalse(base.isFullyConfirmed)

        // Seeker confirmed, investor hasn't yet
        var seekerOnly = base
        seekerOnly.seekerMarkedReceivedAt = Date(timeIntervalSince1970: 1_710_100_000)
        XCTAssertFalse(seekerOnly.isFullyConfirmed)

        // Investor confirmed, seeker hasn't yet
        var investorOnly = base
        investorOnly.investorMarkedPaidAt = Date(timeIntervalSince1970: 1_710_100_000)
        XCTAssertFalse(investorOnly.isFullyConfirmed)

        // Both confirmed → fully confirmed
        var both = base
        both.investorMarkedPaidAt = Date(timeIntervalSince1970: 1_710_100_000)
        both.seekerMarkedReceivedAt = Date(timeIntervalSince1970: 1_710_200_000)
        XCTAssertTrue(both.isFullyConfirmed)
    }
}
