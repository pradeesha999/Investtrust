import Foundation

/// Tracks the MOA lifecycle on the investment document (`agreementStatus`).
enum AgreementStatus: String, Codable, Sendable, CaseIterable {
    case none
    case pending_signatures
    case active
}

/// Tracks post-signature funding and repayment readiness for loan deals.
enum FundingStatus: String, Codable, Sendable, CaseIterable {
    case none
    case awaiting_disbursement
    case disbursed
    case defaulted
    case closed
}

/// Distinguishes a default listing request from a negotiated offer request.
enum InvestmentRequestKind: String, Codable, Sendable, CaseIterable {
    case default_request
    case offer_request
}

enum InvestmentOfferStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case accepted
    case declined
    case superseded
}

enum InvestmentOfferSource: String, Codable, Sendable, CaseIterable {
    case chat
    case detail_sheet
}

/// Structured agreement snapshot stored on the investment at seeker acceptance (no PDF).
struct InvestmentAgreementSnapshot: Equatable, Hashable, Sendable {
    var opportunityTitle: String
    var investorName: String
    var seekerName: String
    var investmentAmount: Double
    var investmentType: InvestmentType
    var termsSnapshot: OpportunityTerms
    var createdAt: Date

    /// Loan repayment cadence from frozen terms (defaults to monthly if unset).
    var loanRepaymentPlan: LoanRepaymentPlan {
        guard investmentType == .loan else { return .monthly }
        return LoanRepaymentPlan.from(termsSnapshot.repaymentFrequency)
    }
}
