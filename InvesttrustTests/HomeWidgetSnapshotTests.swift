import XCTest
@testable import Investtrust

// Tests for the home screen widget snapshot.
// The snapshot is written by the app and read by the widget extension via the shared App Group.
final class HomeWidgetSnapshotTests: XCTestCase {

    func testJSONRoundTripPreservesFields() throws {
        // Writing the snapshot to JSON and reading it back should produce the exact same data
        let original = HomeWidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000),
            activeProfile: "seeker",
            isSignedIn: true,
            investorEvents: [
                HomeWidgetEvent(
                    date: Date(timeIntervalSince1970: 1_710_500_000),
                    amount: 12_500,
                    title: "Installment #2 due",
                    isProjected: false
                )
            ],
            seekerEvents: [
                HomeWidgetEvent(
                    date: Date(timeIntervalSince1970: 1_711_000_000),
                    amount: 5_000,
                    title: "Pay-out window",
                    isProjected: true
                )
            ]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeWidgetSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.activeProfile, "seeker")
        XCTAssertTrue(decoded.isSignedIn)
        XCTAssertEqual(decoded.investorEvents.count, 1)
        XCTAssertEqual(decoded.seekerEvents.count, 1)
    }

    func testMakeSignedOut_producesEmptySignedOutSnapshot() {
        // When the user signs out, the widget should show a signed-out state with no events
        let snapshot = HomeWidgetSnapshot.makeSignedOut()
        XCTAssertFalse(snapshot.isSignedIn)
        XCTAssertEqual(snapshot.activeProfile, "investor")
        XCTAssertTrue(snapshot.investorEvents.isEmpty)
        XCTAssertTrue(snapshot.seekerEvents.isEmpty)
    }

    func testMakeEmptySignedIn_carriesActiveProfileString() {
        // After sign-in but before data loads, the widget shows the correct profile mode with no events
        let snapshot = HomeWidgetSnapshot.makeEmptySignedIn(activeProfile: "seeker")
        XCTAssertTrue(snapshot.isSignedIn)
        XCTAssertEqual(snapshot.activeProfile, "seeker")
        XCTAssertTrue(snapshot.investorEvents.isEmpty)
        XCTAssertTrue(snapshot.seekerEvents.isEmpty)
    }
}
