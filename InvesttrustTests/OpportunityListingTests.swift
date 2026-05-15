import XCTest
@testable import Investtrust

// Tests for the display helpers on an opportunity listing —
// the labels, amounts, and selection logic shown on the market browse and detail screens.
final class OpportunityListingTests: XCTestCase {

    func testNormalizedListingStatus_lowercaseAndBlankBecomesOpen() {
        // Status strings from Firestore may be mixed-case or blank; both should be handled gracefully
        XCTAssertEqual(makeOpportunity(status: "OPEN").normalizedListingStatus, "open")
        XCTAssertEqual(makeOpportunity(status: "  ").normalizedListingStatus, "open")
        XCTAssertEqual(makeOpportunity(status: "Closed").normalizedListingStatus, "closed")
    }

    func testIsOpenForInvesting_onlyTrueForOpen() {
        // The "Invest" button is only enabled when the listing is open
        XCTAssertTrue(makeOpportunity(status: "open").isOpenForInvesting)
        XCTAssertTrue(makeOpportunity(status: "").isOpenForInvesting, "Blank status is treated as open")
        XCTAssertFalse(makeOpportunity(status: "closed").isOpenForInvesting)
    }

    func testRepaymentLabel_forLoanAndEquity() {
        // The short label shown under the funding goal on browse cards
        let loan = makeOpportunity(
            investmentType: .loan,
            terms: OpportunityTerms(interestRate: 12, repaymentTimelineMonths: 18, repaymentFrequency: .monthly)
        )
        XCTAssertEqual(loan.repaymentLabel, "18 months")

        var equityTerms = OpportunityTerms()
        equityTerms.equityPercentage = 15
        equityTerms.equityRoiTimeline = .one_year
        let equity = makeOpportunity(investmentType: .equity, terms: equityTerms)
        XCTAssertTrue(equity.repaymentLabel.contains("ROI"))
    }

    func testTermsSummaryLine_forLoanAndEquity() {
        // The summary line shown on the opportunity detail sheet (e.g. "12% · 24 mo · monthly")
        let loan = makeOpportunity(
            investmentType: .loan,
            terms: OpportunityTerms(interestRate: 12, repaymentTimelineMonths: 24, repaymentFrequency: .monthly)
        )
        let summary = loan.termsSummaryLine
        XCTAssertTrue(summary.contains("12"), "Loan summary should include rate. Got: \(summary)")
        XCTAssertTrue(summary.contains("24"), "Loan summary should include term. Got: \(summary)")

        var equityTerms = OpportunityTerms()
        equityTerms.equityPercentage = 10
        equityTerms.businessValuation = 500_000
        equityTerms.equityRoiTimeline = .two_years
        let equity = makeOpportunity(investmentType: .equity, terms: equityTerms)
        let equitySummary = equity.termsSummaryLine
        XCTAssertTrue(equitySummary.contains("equity"))
        XCTAssertTrue(equitySummary.contains("Val."))
    }

    func testFormattedAmounts_areIntegerWithoutDecimals() {
        // Amounts shown on the listing card must display as whole numbers (no decimals)
        let listing = makeOpportunity(amountRequested: 1_234_567.50, minimumInvestment: 1_000.5)
        XCTAssertFalse(listing.formattedAmountLKR.contains("."), "Amount must not include decimals")
        XCTAssertFalse(listing.formattedAmountLKR.isEmpty)
        XCTAssertFalse(listing.formattedMinimumLKR.contains("."))
    }

    func testListingMinimumTicket_equalSplitsWhenMultipleSlots() {
        // When a listing allows multiple investors, each investor's minimum is the goal divided by slot count
        let ticket = OpportunityListing.listingMinimumTicket(amountRequested: 1_000_000, maximumInvestors: 4)
        XCTAssertEqual(ticket, 250_000, accuracy: 0.01)
    }

    func testListingMinimumTicket_returnsFullGoalForSingleSlot() {
        // A single-investor listing requires the full amount from that investor
        XCTAssertEqual(
            OpportunityListing.listingMinimumTicket(amountRequested: 500_000, maximumInvestors: nil),
            500_000,
            accuracy: 0.01
        )
        XCTAssertEqual(
            OpportunityListing.listingMinimumTicket(amountRequested: 500_000, maximumInvestors: 1),
            500_000,
            accuracy: 0.01
        )
    }

    func testPrimarySeekerDisplayInvestment_picksLatestAcceptedRow() {
        // The seeker's deal card should show the most recently accepted investment
        let earlier = sampleInvestment(
            id: "inv-old",
            status: "accepted",
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let later = sampleInvestment(
            id: "inv-new",
            status: "accepted",
            acceptedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let pending = sampleInvestment(id: "inv-pending", status: "pending")

        let primary = OpportunityListing.primarySeekerDisplayInvestment(rowsForSameOpportunity: [pending, earlier, later])
        XCTAssertEqual(primary?.id, "inv-new")
    }

    func testWithSeekerAcceptedEconomics_overridesAmountAndTerms() {
        // After the seeker accepts a negotiated offer, the listing card should reflect the agreed terms
        let listing = makeOpportunity(
            investmentType: .loan,
            amountRequested: 100_000,
            terms: OpportunityTerms(interestRate: 10, repaymentTimelineMonths: 6, repaymentFrequency: .monthly)
        )
        let accepted = sampleInvestment(
            id: "inv-1",
            status: "accepted",
            offeredAmount: 250_000,
            offeredInterestRate: 15,
            offeredTimelineMonths: 24
        )

        let updated = listing.withSeekerAcceptedEconomics(from: accepted)
        XCTAssertEqual(updated.amountRequested, 250_000, accuracy: 0.01)
        XCTAssertEqual(updated.terms.interestRate, 15)
        XCTAssertEqual(updated.terms.repaymentTimelineMonths, 24)
    }

    // Helpers

    private func makeOpportunity(
        id: String = "opp-1",
        status: String = "open",
        investmentType: InvestmentType = .loan,
        amountRequested: Double = 100_000,
        minimumInvestment: Double = 100_000,
        maximumInvestors: Int? = nil,
        terms: OpportunityTerms = OpportunityTerms(interestRate: 12, repaymentTimelineMonths: 12, repaymentFrequency: .monthly)
    ) -> OpportunityListing {
        OpportunityListing(
            id: id,
            ownerId: "seeker-1",
            title: "Retail expansion",
            category: "Retail",
            description: "Test description",
            investmentType: investmentType,
            amountRequested: amountRequested,
            minimumInvestment: minimumInvestment,
            maximumInvestors: maximumInvestors,
            terms: terms,
            useOfFunds: "Inventory",
            incomeGenerationMethod: "Sales",
            milestones: [],
            location: "Colombo",
            riskLevel: .medium,
            verificationStatus: .unverified,
            isNegotiable: true,
            documentURLs: [],
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            imageStoragePaths: [],
            videoStoragePath: nil,
            videoURL: nil,
            mediaWarnings: [],
            imagePublicIds: [],
            videoPublicId: nil
        )
    }

    private func sampleInvestment(
        id: String,
        status: String,
        acceptedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        offeredAmount: Double? = nil,
        offeredInterestRate: Double? = nil,
        offeredTimelineMonths: Int? = nil
    ) -> InvestmentListing {
        InvestmentListing(
            id: id,
            status: status,
            createdAt: acceptedAt ?? Date(timeIntervalSince1970: 1_700_000_000),
            opportunityId: "opp-1",
            investorId: "investor-\(id)",
            seekerId: "seeker-1",
            opportunityTitle: "Retail expansion",
            imageURLs: [],
            investmentAmount: 100_000,
            finalInterestRate: nil,
            finalTimelineMonths: nil,
            investmentType: .loan,
            acceptedAt: acceptedAt,
            receivedAmount: 0,
            requestKind: offeredAmount != nil ? .offer_request : .default_request,
            offerStatus: .pending,
            offerSource: nil,
            offeredAmount: offeredAmount,
            offeredInterestRate: offeredInterestRate,
            offeredTimelineMonths: offeredTimelineMonths,
            offerDescription: nil,
            offerChatId: nil,
            offerChatMessageId: nil,
            agreementStatus: .none,
            fundingStatus: .none,
            signedByInvestorAt: nil,
            signedBySeekerAt: nil,
            agreementGeneratedAt: nil,
            agreement: nil,
            loanInstallments: [],
            revenueSharePeriods: [],
            moaPdfURL: nil,
            moaContentHash: nil,
            investorSignatureImageURL: nil,
            seekerSignatureImageURL: nil,
            principalSentByInvestorAt: nil,
            principalReceivedBySeekerAt: nil,
            principalInvestorProofImageURLs: [],
            principalSeekerProofImageURLs: []
        )
    }
}
