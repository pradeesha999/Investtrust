import FirebaseCore
import FirebaseFirestore
import XCTest
@testable import Investtrust

/// Reproduces the exact data shape that `InvestmentService.createOrUpdateOfferRequest`
/// writes to Firestore, then verifies the seeker-side parsing surfaces the offered
/// values (not listing defaults).
///
/// This is an offline test — we never hit Firestore. We assemble the same dictionary
/// the service builds, hand it to `InvestmentListing(id:data:)`, and assert the
/// computed properties used by the seeker UI return what the investor typed.
final class InvestmentOfferFlowTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        // FieldValue / Timestamp need Firebase configured even in unit tests.
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

    /// Investor types `100,000 / 18% / 24 months`. The seeker should see exactly that,
    /// not the listing defaults of `123,123 / 20% / 3 months`.
    func test_offerWriteShape_seekerReadsOfferedValues_notListingDefaults() throws {
        let now = Date()
        let payload = makeOfferPayload(
            opportunityId: "opp-1",
            ownerId: "seeker-1",
            investorId: "investor-1",
            investorEnteredAmount: 100_000,
            investorEnteredRate: 18,
            investorEnteredMonths: 24,
            opportunityTitle: "Retail expansion",
            now: now
        )

        let listing = try XCTUnwrap(
            InvestmentListing(id: "inv-new", data: payload),
            "Failed to parse offer payload"
        )

        XCTAssertEqual(listing.requestKind, .offer_request,
                       "requestKind should be offer_request — controls 'Offer pending' label on seeker")
        XCTAssertTrue(listing.isOfferRequest,
                      "isOfferRequest must be true so seeker sees 'Offer pending' instead of 'Pending decision'")
        XCTAssertEqual(listing.offeredAmount, 100_000,
                       "offeredAmount must be persisted from investor input")
        XCTAssertEqual(listing.offeredInterestRate, 18,
                       "offeredInterestRate must be persisted from investor input")
        XCTAssertEqual(listing.offeredTimelineMonths, 24,
                       "offeredTimelineMonths must be persisted from investor input")

        XCTAssertEqual(listing.effectiveAmount, 100_000,
                       "Seeker reads effectiveAmount → must equal offeredAmount, not listing default")
        XCTAssertEqual(listing.effectiveFinalInterestRate, 18,
                       "Seeker reads effectiveFinalInterestRate → must equal offered rate")
        XCTAssertEqual(listing.effectiveFinalTimelineMonths, 24,
                       "Seeker reads effectiveFinalTimelineMonths → must equal offered months")
    }

    /// Repro for the user's screenshot: a row tagged "Pending decision" with
    /// listing-default values is necessarily a *standard* request — the offer fields
    /// are missing — proving the offer create path was never invoked for that row.
    func test_standardRequestRow_lacksOfferFields_andShowsPendingDecisionLabel() throws {
        let payload = makeStandardRequestPayload(
            opportunityId: "opp-1",
            ownerId: "seeker-1",
            investorId: "investor-1",
            listingAmount: 123_123,
            listingRate: 20,
            listingMonths: 3,
            opportunityTitle: "Retail expansion",
            now: Date()
        )

        let listing = try XCTUnwrap(
            InvestmentListing(id: "inv-old", data: payload),
            "Failed to parse standard request payload"
        )

        XCTAssertFalse(listing.isOfferRequest,
                       "Standard request must not be classified as an offer")
        XCTAssertNil(listing.offeredAmount)
        XCTAssertNil(listing.offeredInterestRate)
        XCTAssertNil(listing.offeredTimelineMonths)
        XCTAssertEqual(listing.effectiveAmount, 123_123,
                       "Standard request shows listing default amount")
        XCTAssertEqual(listing.effectiveFinalInterestRate, 20)
        XCTAssertEqual(listing.effectiveFinalTimelineMonths, 3)

        XCTAssertEqual(seekerStatusLabel(for: listing), "Pending decision",
                       "Standard pending → seeker label is 'Pending decision' (matches user's screenshot)")
    }

    /// When BOTH a stale standard pending row and a fresh offer pending row exist for
    /// the same investor, the dedup logic must surface the offer so the seeker sees
    /// the latest negotiated terms.
    func test_pendingDedup_prefersOfferOverStandardForSameInvestor() throws {
        let now = Date()
        let standard = try XCTUnwrap(InvestmentListing(
            id: "inv-old",
            data: makeStandardRequestPayload(
                opportunityId: "opp-1",
                ownerId: "seeker-1",
                investorId: "investor-1",
                listingAmount: 123_123,
                listingRate: 20,
                listingMonths: 3,
                opportunityTitle: "Retail expansion",
                now: now.addingTimeInterval(-3_600)
            )
        ))
        let offer = try XCTUnwrap(InvestmentListing(
            id: "inv-new",
            data: makeOfferPayload(
                opportunityId: "opp-1",
                ownerId: "seeker-1",
                investorId: "investor-1",
                investorEnteredAmount: 100_000,
                investorEnteredRate: 18,
                investorEnteredMonths: 24,
                opportunityTitle: "Retail expansion",
                now: now
            )
        ))

        let preferred = preferredPendingRow(standard, offer)
        XCTAssertEqual(preferred.id, "inv-new",
                       "Offer row must win over standard row for same investor")
        XCTAssertEqual(preferred.effectiveAmount, 100_000)
    }

    // MARK: - Helpers (mirror InvestmentService payload shapes 1:1)

    private func makeOfferPayload(
        opportunityId: String,
        ownerId: String,
        investorId: String,
        investorEnteredAmount: Double,
        investorEnteredRate: Double,
        investorEnteredMonths: Int,
        opportunityTitle: String,
        now: Date
    ) -> [String: Any] {
        [
            "opportunityId": opportunityId,
            "opportunity": ["id": opportunityId, "ownerId": ownerId] as [String: Any],
            "investorId": investorId,
            "seekerId": ownerId,
            "status": "pending",
            "agreementStatus": AgreementStatus.none.rawValue,
            "fundingStatus": FundingStatus.none.rawValue,
            "requestKind": InvestmentRequestKind.offer_request.rawValue,
            "offerStatus": InvestmentOfferStatus.pending.rawValue,
            "isOfferRequest": true,
            "offerSource": InvestmentOfferSource.detail_sheet.rawValue,
            "offeredAmount": investorEnteredAmount,
            "offeredInterestRate": investorEnteredRate,
            "offeredTimelineMonths": investorEnteredMonths,
            "offerDescription": "",
            "offer": [
                "isOffer": true,
                "amount": investorEnteredAmount,
                "interestRate": investorEnteredRate,
                "timelineMonths": investorEnteredMonths,
                "description": "",
                "source": InvestmentOfferSource.detail_sheet.rawValue,
                "updatedAt": Timestamp(date: now)
            ] as [String: Any],
            "investmentAmount": investorEnteredAmount,
            "finalInterestRate": investorEnteredRate,
            "finalTimelineMonths": investorEnteredMonths,
            "investmentType": InvestmentType.loan.rawValue,
            "opportunityInvestmentType": InvestmentType.loan.rawValue,
            "receivedAmount": 0,
            "opportunityTitle": opportunityTitle,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now),
            "loanInstallments": [],
            "revenueSharePeriods": []
        ]
    }

    private func makeStandardRequestPayload(
        opportunityId: String,
        ownerId: String,
        investorId: String,
        listingAmount: Double,
        listingRate: Double,
        listingMonths: Int,
        opportunityTitle: String,
        now: Date
    ) -> [String: Any] {
        [
            "opportunityId": opportunityId,
            "opportunity": ["id": opportunityId, "ownerId": ownerId] as [String: Any],
            "investorId": investorId,
            "seekerId": ownerId,
            "status": "pending",
            "agreementStatus": AgreementStatus.none.rawValue,
            "fundingStatus": FundingStatus.none.rawValue,
            "requestKind": InvestmentRequestKind.default_request.rawValue,
            "offerStatus": InvestmentOfferStatus.pending.rawValue,
            "isOfferRequest": false,
            "investmentAmount": listingAmount,
            "finalInterestRate": listingRate,
            "finalTimelineMonths": listingMonths,
            "investmentType": InvestmentType.loan.rawValue,
            "opportunityInvestmentType": InvestmentType.loan.rawValue,
            "receivedAmount": 0,
            "opportunityTitle": opportunityTitle,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now),
            "loanInstallments": [],
            "revenueSharePeriods": []
        ]
    }

    /// Mirrors `SeekerOpportunityDetailView.requestStatusLabel` exactly.
    private func seekerStatusLabel(for inv: InvestmentListing) -> String {
        if inv.status.lowercased() == "pending" {
            return inv.isOfferRequest ? "Offer pending" : "Pending decision"
        }
        return inv.lifecycleDisplayTitle
    }

    /// Mirrors `SeekerOpportunityDetailView.pendingRequestRows` per-investor preference.
    private func preferredPendingRow(_ a: InvestmentListing, _ b: InvestmentListing) -> InvestmentListing {
        if a.isOfferRequest != b.isOfferRequest {
            return a.isOfferRequest ? a : b
        }
        return a.recencyDate > b.recencyDate ? a : b
    }
}
