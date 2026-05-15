import FirebaseCore
import FirebaseFirestore
import XCTest
@testable import Investtrust

// Tests for reading and writing opportunity data in Firestore.
// Covers enum parsing, loan vs equity terms encoding, and milestone ordering.
final class OpportunitySchemaTests: XCTestCase {

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

    func testInvestmentTypeParse_defaultsToLoanOnBadInput() {
        // Missing or unrecognised type strings should default to "loan" so the app never crashes
        XCTAssertEqual(InvestmentType.parse(nil), .loan)
        XCTAssertEqual(InvestmentType.parse(""), .loan)
        XCTAssertEqual(InvestmentType.parse("garbage"), .loan)
        XCTAssertEqual(InvestmentType.parse("equity"), .equity)
        XCTAssertEqual(InvestmentType.parse("LOAN"), .loan)
    }

    func testRiskLevelParse_defaultsToMediumOnBadInput() {
        // Unknown risk level strings default to medium
        XCTAssertEqual(RiskLevel.parse(nil), .medium)
        XCTAssertEqual(RiskLevel.parse(""), .medium)
        XCTAssertEqual(RiskLevel.parse("unknown"), .medium)
        XCTAssertEqual(RiskLevel.parse("HIGH"), .high)
    }

    func testVerificationStatusParse_defaultsToUnverified() {
        // Unknown verification strings default to unverified
        XCTAssertEqual(VerificationStatus.parse(nil), .unverified)
        XCTAssertEqual(VerificationStatus.parse(""), .unverified)
        XCTAssertEqual(VerificationStatus.parse("bogus"), .unverified)
        XCTAssertEqual(VerificationStatus.parse("verified"), .verified)
    }

    func testTermsDictionary_loanIncludesLoanFieldsOnly() {
        // Saving a loan listing should not include equity-specific fields in the terms map
        let terms = OpportunityTerms(
            interestRate: 12,
            repaymentTimelineMonths: 18,
            repaymentFrequency: .monthly,
            equityPercentage: 10,
            businessValuation: 1_000_000
        )
        let map = OpportunityFirestoreCoding.termsDictionary(from: terms, type: .loan)
        XCTAssertEqual(map["interestRate"] as? Double, 12)
        XCTAssertEqual(map["repaymentTimelineMonths"] as? Int, 18)
        XCTAssertEqual(map["repaymentFrequency"] as? String, "monthly")
        XCTAssertNil(map["equityPercentage"], "Loan dictionary should not include equity fields")
        XCTAssertNil(map["businessValuation"])
    }

    func testTermsDictionary_equityIncludesEquityFieldsOnly() {
        // Saving an equity listing should not include loan-specific fields in the terms map
        var terms = OpportunityTerms()
        terms.equityPercentage = 12.5
        terms.businessValuation = 2_000_000
        terms.equityTimelineMonths = 24
        terms.ventureName = "FinTech Co"
        terms.ventureStage = .scaling
        terms.equityRoiTimeline = .two_years
        terms.exitPlan = "Acquisition or IPO"
        // These loan fields should be excluded from the equity terms map
        terms.interestRate = 99
        terms.repaymentTimelineMonths = 99

        let map = OpportunityFirestoreCoding.termsDictionary(from: terms, type: .equity)
        XCTAssertEqual(map["equityPercentage"] as? Double, 12.5)
        XCTAssertEqual(map["businessValuation"] as? Double, 2_000_000)
        XCTAssertEqual(map["equityTimelineMonths"] as? Int, 24)
        XCTAssertEqual(map["ventureName"] as? String, "FinTech Co")
        XCTAssertEqual(map["ventureStage"] as? String, "scaling")
        XCTAssertEqual(map["equityRoiTimeline"] as? String, "two_years")
        XCTAssertEqual(map["exitPlan"] as? String, "Acquisition or IPO")
        XCTAssertNil(map["interestRate"])
        XCTAssertNil(map["repaymentTimelineMonths"])
    }

    func testParseTerms_readsNestedTermsBlock() {
        // New documents store terms under a "terms" sub-object
        let data: [String: Any] = [
            "terms": [
                "interestRate": 12.5,
                "repaymentTimelineMonths": 18,
                "repaymentFrequency": "weekly"
            ]
        ]
        let parsed = OpportunityFirestoreCoding.parseTerms(from: data, type: .loan)
        XCTAssertEqual(parsed.interestRate, 12.5)
        XCTAssertEqual(parsed.repaymentTimelineMonths, 18)
        XCTAssertEqual(parsed.repaymentFrequency, .weekly)
    }

    func testParseTerms_fallsBackToLegacyFlatFields() {
        // Old documents stored terms at the root level; those should still be readable
        let data: [String: Any] = [
            "interestRate": 9.0,
            "repaymentTimelineMonths": 6
        ]
        let parsed = OpportunityFirestoreCoding.parseTerms(from: data, type: .loan)
        XCTAssertEqual(parsed.interestRate, 9.0)
        XCTAssertEqual(parsed.repaymentTimelineMonths, 6)
    }

    func testMilestones_sortsByDaysAfterAcceptanceThenExpectedDateThenUndated() {
        // Milestones on the deal timeline are sorted: day-anchored first, then dated, then open-ended
        let dayBased = OpportunityMilestone(
            title: "Day 30 follow-up",
            description: "30 days after acceptance",
            expectedDate: nil,
            dueDaysAfterAcceptance: 30
        )
        let dayBasedEarlier = OpportunityMilestone(
            title: "Day 10 follow-up",
            description: "10 days after acceptance",
            expectedDate: nil,
            dueDaysAfterAcceptance: 10
        )
        let dateBased = OpportunityMilestone(
            title: "Legacy",
            description: "Legacy date",
            expectedDate: Date(timeIntervalSince1970: 1_705_000_000),
            dueDaysAfterAcceptance: nil
        )
        let undated = OpportunityMilestone(
            title: "Open ended",
            description: "No date",
            expectedDate: nil,
            dueDaysAfterAcceptance: nil
        )

        let sorted = OpportunityFirestoreCoding.sortedMilestonesChronologically(
            [undated, dateBased, dayBased, dayBasedEarlier]
        )
        XCTAssertEqual(sorted.map(\.title), ["Day 10 follow-up", "Day 30 follow-up", "Legacy", "Open ended"])
    }

    func testMilestones_decodingFromFirestoreRespectsDaysAfterAcceptance() {
        // Empty title/description rows should be dropped; valid rows should decode correctly
        let data: [String: Any] = [
            "milestones": [
                [
                    "title": "Open pop-up store",
                    "description": "First public sale",
                    "daysAfterAcceptance": 45
                ],
                [
                    "title": "",
                    "description": ""
                ]
            ]
        ]
        let milestones = OpportunityFirestoreCoding.milestones(from: data)
        XCTAssertEqual(milestones.count, 1)
        XCTAssertEqual(milestones.first?.title, "Open pop-up store")
        XCTAssertEqual(milestones.first?.dueDaysAfterAcceptance, 45)
    }

    func testMilestonesPayload_emitsDaysWhenNonNegative() {
        // When saving milestones, day-anchored rows must include daysAfterAcceptance; undated rows must not
        let payload = OpportunityFirestoreCoding.milestonesPayload([
            OpportunityMilestone(
                title: "Day-anchored",
                description: "10 days after",
                expectedDate: nil,
                dueDaysAfterAcceptance: 10
            ),
            OpportunityMilestone(
                title: "No anchor",
                description: "",
                expectedDate: nil,
                dueDaysAfterAcceptance: nil
            )
        ])

        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload[0]["daysAfterAcceptance"] as? Int, 10)
        XCTAssertNil(payload[1]["daysAfterAcceptance"])
    }
}
