import XCTest
@testable import Investtrust

// Tests for the status labels and display logic shown on investment cards
// throughout the app — deal title, amounts, seeker gates, and repayment surface.
final class InvestmentLifecycleTests: XCTestCase {

    func testLifecycleDisplayTitle_pickedFromStatusAndAgreement() {
        // The title shown on the investor's deal card changes as the deal moves through each stage
        XCTAssertEqual(makeListing(status: "pending").lifecycleDisplayTitle, "Waiting for seeker")
        XCTAssertEqual(makeListing(status: "accepted").lifecycleDisplayTitle, "Accepted")
        XCTAssertEqual(makeListing(status: "declined").lifecycleDisplayTitle, "Declined")
        XCTAssertEqual(makeListing(status: "completed").lifecycleDisplayTitle, "Agreement completed")
        XCTAssertEqual(
            makeListing(status: "accepted", agreementStatus: .pending_signatures).lifecycleDisplayTitle,
            "Awaiting signatures"
        )
        XCTAssertEqual(
            makeListing(status: "active", agreementStatus: .active).lifecycleDisplayTitle,
            "Agreement active"
        )
        // Once funding is closed the deal is always shown as completed, regardless of other status fields
        XCTAssertEqual(
            makeListing(status: "active", agreementStatus: .active, fundingStatus: .closed).lifecycleDisplayTitle,
            "Agreement completed"
        )
    }

    func testEffectiveValues_preferOfferOverLegacyFields() {
        // When an investor makes a counter-offer, the offered values should override the original request
        let listing = makeListing(
            investmentAmount: 100_000,
            finalInterestRate: 10,
            finalTimelineMonths: 12,
            offeredAmount: 200_000,
            offeredInterestRate: 14,
            offeredTimelineMonths: 24
        )
        XCTAssertEqual(listing.effectiveAmount, 200_000)
        XCTAssertEqual(listing.effectiveFinalInterestRate, 14)
        XCTAssertEqual(listing.effectiveFinalTimelineMonths, 24)
    }

    func testEffectiveValues_fallBackToLegacyWhenNoOffer() {
        // When there's no counter-offer, the original request values are used
        let listing = makeListing(
            investmentAmount: 100_000,
            finalInterestRate: 10,
            finalTimelineMonths: 12
        )
        XCTAssertEqual(listing.effectiveAmount, 100_000)
        XCTAssertEqual(listing.effectiveFinalInterestRate, 10)
        XCTAssertEqual(listing.effectiveFinalTimelineMonths, 12)
    }

    func testBlocksSeekerFromManagingOpportunity_forActiveStates() {
        // While a request is pending or accepted the seeker can't edit/delete the opportunity
        XCTAssertTrue(makeListing(status: "pending").blocksSeekerFromManagingOpportunity)
        XCTAssertTrue(makeListing(status: "accepted").blocksSeekerFromManagingOpportunity)
        // Declined or withdrawn requests lift the lock
        XCTAssertFalse(makeListing(status: "declined").blocksSeekerFromManagingOpportunity)
        XCTAssertFalse(makeListing(status: "withdrawn").blocksSeekerFromManagingOpportunity)
        XCTAssertFalse(makeListing(status: "cancelled").blocksSeekerFromManagingOpportunity)
    }

    func testTriggersSeekerRequestResolutionBanner_excludesActiveAgreements() {
        // The "resolve pending requests" banner shows for pending requests but not for live deals
        let pending = makeListing(status: "pending")
        XCTAssertTrue(pending.triggersSeekerRequestResolutionBanner)

        let activeAgreement = makeListing(status: "active", agreementStatus: .active)
        XCTAssertFalse(activeAgreement.triggersSeekerRequestResolutionBanner)

        let completed = makeListing(status: "completed")
        XCTAssertFalse(completed.triggersSeekerRequestResolutionBanner)
    }

    func testIsLoanWithSchedule_requiresLoanTypeAndInstallments() {
        // The repayment schedule tab is only shown for loan deals that already have installments generated
        let withSchedule = makeListing(loanInstallments: [sampleInstallment(no: 1)])
        XCTAssertTrue(withSchedule.isLoanWithSchedule)

        let withoutSchedule = makeListing(loanInstallments: [])
        XCTAssertFalse(withoutSchedule.isLoanWithSchedule)

        // Equity deals never show the loan repayment tab
        let equity = makeListing(investmentType: .equity, loanInstallments: [sampleInstallment(no: 1)])
        XCTAssertFalse(equity.isLoanWithSchedule)
    }

    func testLoanRepaymentsUnlocked_forDisbursedClosedDefaulted() {
        // The repayment flow unlocks once the investor has disbursed funds
        XCTAssertTrue(makeListing(fundingStatus: .disbursed).loanRepaymentsUnlocked)
        XCTAssertTrue(makeListing(fundingStatus: .closed).loanRepaymentsUnlocked)
        XCTAssertTrue(makeListing(fundingStatus: .defaulted).loanRepaymentsUnlocked)
        XCTAssertFalse(makeListing(fundingStatus: .awaiting_disbursement).loanRepaymentsUnlocked)
        XCTAssertFalse(makeListing(fundingStatus: .none).loanRepaymentsUnlocked)
        // Equity deals must never show the loan repayment UI
        XCTAssertFalse(
            makeListing(investmentType: .equity, fundingStatus: .closed).loanRepaymentsUnlocked,
            "Equity rows should not unlock loan repayment UI"
        )
    }

    func testNextOpenLoanInstallment_skipsConfirmedAndReturnsEarliest() {
        // The "next payment" card should skip already-confirmed installments
        let earlier = sampleInstallment(
            no: 1,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            status: .confirmed_paid
        )
        let middle = sampleInstallment(
            no: 2,
            dueDate: Date(timeIntervalSince1970: 1_705_000_000),
            status: .awaiting_confirmation
        )
        let later = sampleInstallment(
            no: 3,
            dueDate: Date(timeIntervalSince1970: 1_710_000_000),
            status: .scheduled
        )
        let listing = makeListing(loanInstallments: [later, middle, earlier])
        XCTAssertEqual(listing.nextOpenLoanInstallment?.installmentNo, 2)
    }

    func testConfirmedLoanRepaymentTotal_sumsOnlyConfirmedRows() {
        // The "total received" figure on the deal screen only counts fully confirmed payments
        let listing = makeListing(loanInstallments: [
            sampleInstallment(no: 1, total: 1_000, status: .confirmed_paid),
            sampleInstallment(no: 2, total: 1_000, status: .awaiting_confirmation),
            sampleInstallment(no: 3, total: 1_500, status: .confirmed_paid)
        ])
        XCTAssertEqual(listing.confirmedLoanRepaymentTotal, 2_500, accuracy: 0.01)
    }

    func testReplacingAgreement_swapsSnapshotPreservingRest() {
        // When a new MOA is generated, only the agreement snapshot is replaced; everything else stays the same
        let firstSnapshot = sampleAgreement(termsHash: "hash-1")
        let secondSnapshot = sampleAgreement(termsHash: "hash-2")

        let listing = makeListing(agreement: firstSnapshot)
        let swapped = listing.replacingAgreement(secondSnapshot)

        XCTAssertEqual(swapped.id, listing.id)
        XCTAssertEqual(swapped.investmentAmount, listing.investmentAmount)
        XCTAssertEqual(swapped.agreement?.termsSnapshotHash, "hash-2")
    }

    // Helpers

    private func makeListing(
        id: String = "inv-1",
        status: String = "pending",
        investmentType: InvestmentType = .loan,
        investmentAmount: Double = 100_000,
        finalInterestRate: Double? = nil,
        finalTimelineMonths: Int? = nil,
        offeredAmount: Double? = nil,
        offeredInterestRate: Double? = nil,
        offeredTimelineMonths: Int? = nil,
        agreementStatus: AgreementStatus = .none,
        fundingStatus: FundingStatus = .none,
        loanInstallments: [LoanInstallment] = [],
        agreement: InvestmentAgreementSnapshot? = nil
    ) -> InvestmentListing {
        InvestmentListing(
            id: id,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            opportunityId: "opp-1",
            investorId: "investor-1",
            seekerId: "seeker-1",
            opportunityTitle: "Retail expansion",
            imageURLs: [],
            investmentAmount: investmentAmount,
            finalInterestRate: finalInterestRate,
            finalTimelineMonths: finalTimelineMonths,
            investmentType: investmentType,
            acceptedAt: nil,
            receivedAmount: 0,
            requestKind: .default_request,
            offerStatus: .pending,
            offerSource: nil,
            offeredAmount: offeredAmount,
            offeredInterestRate: offeredInterestRate,
            offeredTimelineMonths: offeredTimelineMonths,
            offerDescription: nil,
            offerChatId: nil,
            offerChatMessageId: nil,
            agreementStatus: agreementStatus,
            fundingStatus: fundingStatus,
            signedByInvestorAt: nil,
            signedBySeekerAt: nil,
            agreementGeneratedAt: nil,
            agreement: agreement,
            loanInstallments: loanInstallments,
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

    private func sampleInstallment(
        no: Int,
        dueDate: Date = Date(timeIntervalSince1970: 1_710_000_000),
        total: Double = 1_000,
        status: LoanInstallmentStatus = .scheduled
    ) -> LoanInstallment {
        LoanInstallment(
            installmentNo: no,
            dueDate: dueDate,
            principalComponent: total - 100,
            interestComponent: 100,
            totalDue: total,
            status: status,
            investorMarkedPaidAt: nil,
            seekerMarkedReceivedAt: nil,
            seekerProofImageURLs: [],
            investorProofImageURLs: []
        )
    }

    private func sampleAgreement(termsHash: String) -> InvestmentAgreementSnapshot {
        InvestmentAgreementSnapshot(
            agreementId: "opp-1",
            agreementVersion: 1,
            termsSnapshotHash: termsHash,
            requiredSignerIds: ["seeker-1", "investor-1"],
            linkedInvestmentIds: [],
            participants: [],
            opportunityTitle: "Retail expansion",
            investorName: "Investor",
            seekerName: "Seeker",
            investmentAmount: 100_000,
            investmentType: .loan,
            termsSnapshot: OpportunityTerms(interestRate: 10, repaymentTimelineMonths: 12),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
