import XCTest
@testable import Investtrust

// Tests for the KPI numbers shown on the investor dashboard —
// total invested, total pending, profit/loss, and deal classification.
final class InvestorPortfolioMetricsTests: XCTestCase {

    func testIsCompletedDeal_trueForClosedLoanAndAllMilestonesCompleteEquity() {
        // A loan deal is complete when funding is closed
        let closedLoan = makeListing(status: "active", fundingStatus: .closed)
        XCTAssertTrue(InvestorPortfolioMetrics.isCompletedDeal(closedLoan))

        // An equity deal is complete only when every milestone has been marked done
        let completedEquity = makeListing(
            status: "active",
            investmentType: .equity,
            equityMilestones: [
                completedMilestone(title: "Phase 1"),
                completedMilestone(title: "Phase 2")
            ]
        )
        XCTAssertTrue(InvestorPortfolioMetrics.isCompletedDeal(completedEquity))

        // Equity with at least one incomplete milestone is not yet complete
        let partialEquity = makeListing(
            status: "active",
            investmentType: .equity,
            equityMilestones: [
                completedMilestone(title: "Phase 1"),
                EquityMilestoneProgress(
                    title: "Phase 2",
                    description: "Still in progress",
                    dueDate: nil,
                    status: .in_progress,
                    updatedAt: nil,
                    note: nil
                )
            ]
        )
        XCTAssertFalse(InvestorPortfolioMetrics.isCompletedDeal(partialEquity))
    }

    func testIsOngoingDeal_excludesPendingAndDeclinedAndCompleted() {
        // Only live deals (active MOA or awaiting signatures) should count as ongoing
        XCTAssertFalse(InvestorPortfolioMetrics.isOngoingDeal(makeListing(status: "pending")))
        XCTAssertFalse(InvestorPortfolioMetrics.isOngoingDeal(makeListing(status: "declined")))
        XCTAssertFalse(InvestorPortfolioMetrics.isOngoingDeal(makeListing(status: "withdrawn")))
        XCTAssertFalse(InvestorPortfolioMetrics.isOngoingDeal(makeListing(status: "active", fundingStatus: .closed)))
        XCTAssertTrue(InvestorPortfolioMetrics.isOngoingDeal(makeListing(status: "active", agreementStatus: .active)))
        XCTAssertTrue(InvestorPortfolioMetrics.isOngoingDeal(makeListing(status: "accepted", agreementStatus: .pending_signatures)))
    }

    func testTotalInvestedInBook_sumsOnlyOngoingRows() {
        // "Total invested" on the dashboard only counts money in live, ongoing deals
        let rows = [
            makeListing(id: "p", status: "pending", investmentAmount: 50_000),
            makeListing(id: "a", status: "active", agreementStatus: .active, investmentAmount: 100_000),
            makeListing(id: "s", status: "accepted", agreementStatus: .pending_signatures, investmentAmount: 25_000),
            makeListing(id: "d", status: "declined", investmentAmount: 1_000_000),
            makeListing(id: "c", status: "active", agreementStatus: .active, fundingStatus: .closed, investmentAmount: 999_999)
        ]
        XCTAssertEqual(InvestorPortfolioMetrics.totalInvestedInBook(rows), 125_000, accuracy: 0.01)
    }

    func testTotalPendingAmount_sumsOnlyPendingRows() {
        // "Pending" amount tile shows only requests still waiting for the seeker to respond
        let rows = [
            makeListing(id: "p1", status: "pending", investmentAmount: 20_000),
            makeListing(id: "p2", status: "pending", investmentAmount: 30_000),
            makeListing(id: "a", status: "active", investmentAmount: 100_000)
        ]
        XCTAssertEqual(InvestorPortfolioMetrics.totalPendingAmount(rows), 50_000, accuracy: 0.01)
    }

    func testPureProfitAllTime_isReceivedMinusInvested() {
        // Net profit = confirmed repayments received − total deployed; negative while repayments are in progress
        let activeWithRepayments = makeListing(
            id: "a",
            status: "active",
            agreementStatus: .active,
            fundingStatus: .disbursed,
            investmentAmount: 100_000,
            loanInstallments: [
                sampleInstallment(no: 1, total: 30_000, status: .confirmed_paid),
                sampleInstallment(no: 2, total: 30_000, status: .scheduled)
            ]
        )
        // LKR 30,000 received – LKR 100,000 invested = –LKR 70,000
        XCTAssertEqual(InvestorPortfolioMetrics.pureProfitAllTime([activeWithRepayments]), -70_000, accuracy: 0.01)
    }

    func testReturnedValue_usesScheduleForLoansAndReceivedAmountOtherwise() {
        // For scheduled loans, only confirmed installments count; for others, use the receivedAmount field
        let scheduledLoan = makeListing(
            investmentType: .loan,
            receivedAmount: 999,
            loanInstallments: [
                sampleInstallment(no: 1, total: 1_000, status: .confirmed_paid),
                sampleInstallment(no: 2, total: 500, status: .scheduled)
            ]
        )
        XCTAssertEqual(InvestorPortfolioMetrics.returnedValue(for: scheduledLoan), 1_000, accuracy: 0.01)

        let legacyRow = makeListing(receivedAmount: 12_500)
        XCTAssertEqual(InvestorPortfolioMetrics.returnedValue(for: legacyRow), 12_500, accuracy: 0.01)
    }

    // Helpers

    private func makeListing(
        id: String = "inv-1",
        status: String = "pending",
        investmentType: InvestmentType = .loan,
        agreementStatus: AgreementStatus = .none,
        fundingStatus: FundingStatus = .none,
        investmentAmount: Double = 100_000,
        receivedAmount: Double = 0,
        loanInstallments: [LoanInstallment] = [],
        equityMilestones: [EquityMilestoneProgress] = []
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
            finalInterestRate: 10,
            finalTimelineMonths: 12,
            investmentType: investmentType,
            acceptedAt: nil,
            receivedAmount: receivedAmount,
            requestKind: .default_request,
            offerStatus: .pending,
            offerSource: nil,
            offeredAmount: nil,
            offeredInterestRate: nil,
            offeredTimelineMonths: nil,
            offerDescription: nil,
            offerChatId: nil,
            offerChatMessageId: nil,
            agreementStatus: agreementStatus,
            fundingStatus: fundingStatus,
            signedByInvestorAt: nil,
            signedBySeekerAt: nil,
            agreementGeneratedAt: nil,
            agreement: nil,
            loanInstallments: loanInstallments,
            revenueSharePeriods: [],
            moaPdfURL: nil,
            moaContentHash: nil,
            investorSignatureImageURL: nil,
            seekerSignatureImageURL: nil,
            principalSentByInvestorAt: nil,
            principalReceivedBySeekerAt: nil,
            principalInvestorProofImageURLs: [],
            principalSeekerProofImageURLs: [],
            equityMilestones: equityMilestones
        )
    }

    private func sampleInstallment(
        no: Int,
        total: Double,
        status: LoanInstallmentStatus
    ) -> LoanInstallment {
        LoanInstallment(
            installmentNo: no,
            dueDate: Date(timeIntervalSince1970: 1_710_000_000 + Double(no) * 86_400 * 30),
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

    private func completedMilestone(title: String) -> EquityMilestoneProgress {
        EquityMilestoneProgress(
            title: title,
            description: "",
            dueDate: nil,
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000),
            note: nil
        )
    }
}
