import XCTest
@testable import Investtrust

// Tests for the funding-amount filter on the market browse screen.
// Each bracket maps to a chip the investor can tap to narrow the listing feed.
final class OpportunityFundingBracketTests: XCTestCase {

    func testAnyBracketAlwaysContains() {
        // "Any amount" filter should never exclude a listing
        XCTAssertTrue(OpportunityFundingBracket.any.contains(amount: 0))
        XCTAssertTrue(OpportunityFundingBracket.any.contains(amount: 1_000_000))
        XCTAssertTrue(OpportunityFundingBracket.any.contains(amount: 100_000_000))
    }

    func testUnder500k_strictlyLessThanHalfMillion() {
        XCTAssertTrue(OpportunityFundingBracket.under500k.contains(amount: 499_999))
        XCTAssertFalse(OpportunityFundingBracket.under500k.contains(amount: 500_000))
    }

    func testFrom500kTo2m_includesBothBounds() {
        XCTAssertTrue(OpportunityFundingBracket.from500kTo2m.contains(amount: 500_000))
        XCTAssertTrue(OpportunityFundingBracket.from500kTo2m.contains(amount: 2_000_000))
        XCTAssertFalse(OpportunityFundingBracket.from500kTo2m.contains(amount: 499_999))
        XCTAssertFalse(OpportunityFundingBracket.from500kTo2m.contains(amount: 2_000_001))
    }

    func testFrom2mTo10m_includesBothBounds() {
        XCTAssertTrue(OpportunityFundingBracket.from2mTo10m.contains(amount: 2_000_000))
        XCTAssertTrue(OpportunityFundingBracket.from2mTo10m.contains(amount: 10_000_000))
        XCTAssertFalse(OpportunityFundingBracket.from2mTo10m.contains(amount: 1_999_999))
        XCTAssertFalse(OpportunityFundingBracket.from2mTo10m.contains(amount: 10_000_001))
    }

    func testOver10m_strictlyGreaterThanTenMillion() {
        XCTAssertTrue(OpportunityFundingBracket.over10m.contains(amount: 10_000_001))
        XCTAssertFalse(OpportunityFundingBracket.over10m.contains(amount: 10_000_000))
    }
}
