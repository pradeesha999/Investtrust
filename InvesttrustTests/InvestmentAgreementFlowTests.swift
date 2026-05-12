import XCTest
@testable import Investtrust

final class InvestmentAgreementFlowTests: XCTestCase {
    func testNeedsSignatureUsesParticipantSnapshot() {
        let agreement = InvestmentAgreementSnapshot(
            agreementId: "opp-1",
            agreementVersion: 1,
            termsSnapshotHash: "abc123",
            requiredSignerIds: ["seeker-1", "investor-1", "investor-2"],
            linkedInvestmentIds: [],
            participants: [
                AgreementSignerSnapshot(
                    signerId: "seeker-1",
                    signerRole: .seeker,
                    displayName: "Seeker",
                    signatureURL: nil,
                    signedAt: nil
                ),
                AgreementSignerSnapshot(
                    signerId: "investor-1",
                    signerRole: .investor,
                    displayName: "Investor A",
                    signatureURL: "https://example.com/investor-a.png",
                    signedAt: Date(timeIntervalSince1970: 1_700_000_100)
                ),
                AgreementSignerSnapshot(
                    signerId: "investor-2",
                    signerRole: .investor,
                    displayName: "Investor B",
                    signatureURL: nil,
                    signedAt: nil
                )
            ],
            opportunityTitle: "Retail expansion",
            investorName: "Investor A",
            seekerName: "Seeker",
            investmentAmount: 250_000,
            investmentType: .loan,
            termsSnapshot: OpportunityTerms(interestRate: 12, repaymentTimelineMonths: 12),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let listing = makeListing(agreement: agreement)

        XCTAssertTrue(listing.needsSeekerSignature(currentUserId: "seeker-1"))
        XCTAssertFalse(listing.needsInvestorSignature(currentUserId: "investor-1"))
        XCTAssertTrue(listing.needsInvestorSignature(currentUserId: "investor-2"))
        XCTAssertEqual(listing.agreementSignedCount, 1)
        XCTAssertEqual(listing.agreementRequiredSignerCount, 3)
    }

    func testNeedsSignatureFallsBackToLegacyFieldsWhenParticipantsMissing() {
        let listing = makeListing(
            signedByInvestorAt: nil,
            signedBySeekerAt: Date(timeIntervalSince1970: 1_700_000_100),
            agreement: nil
        )

        XCTAssertTrue(listing.needsInvestorSignature(currentUserId: "investor-1"))
        XCTAssertFalse(listing.needsSeekerSignature(currentUserId: "seeker-1"))
        XCTAssertEqual(listing.agreementSignedCount, 1)
        XCTAssertEqual(listing.agreementRequiredSignerCount, 2)
    }

    private func makeListing(
        signedByInvestorAt: Date? = nil,
        signedBySeekerAt: Date? = nil,
        agreement: InvestmentAgreementSnapshot? = nil
    ) -> InvestmentListing {
        InvestmentListing(
            id: "inv-1",
            status: "accepted",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            opportunityId: "opp-1",
            investorId: "investor-1",
            seekerId: "seeker-1",
            opportunityTitle: "Retail expansion",
            imageURLs: [],
            investmentAmount: 250_000,
            finalInterestRate: 12,
            finalTimelineMonths: 12,
            investmentType: .loan,
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_050),
            receivedAmount: 0,
            requestKind: .default_request,
            offerStatus: .pending,
            offerSource: nil,
            offeredAmount: nil,
            offeredInterestRate: nil,
            offeredTimelineMonths: nil,
            offerDescription: nil,
            offerChatId: nil,
            offerChatMessageId: nil,
            agreementStatus: .pending_signatures,
            fundingStatus: .none,
            signedByInvestorAt: signedByInvestorAt,
            signedBySeekerAt: signedBySeekerAt,
            agreementGeneratedAt: Date(timeIntervalSince1970: 1_700_000_060),
            agreement: agreement,
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
