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

enum AgreementSignerRole: String, Codable, Sendable, CaseIterable {
    case seeker
    case investor
}

struct AgreementSignerSnapshot: Equatable, Hashable, Sendable, Codable {
    var signerId: String
    var signerRole: AgreementSignerRole
    var displayName: String
    var signatureURL: String?
    var signedAt: Date?

    var isSigned: Bool {
        signedAt != nil && !(signatureURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Structured agreement snapshot stored on the investment at seeker acceptance (no PDF).
struct InvestmentAgreementSnapshot: Equatable, Hashable, Sendable {
    /// Opportunity scoped agreement id (e.g. `opportunityId`).
    var agreementId: String
    /// Agreement schema/template version for backward compatibility.
    var agreementVersion: Int
    /// Deterministic digest for frozen terms and core economics.
    var termsSnapshotHash: String
    /// Required signer user IDs.
    var requiredSignerIds: [String]
    /// Snapshot of all participants and their signature state.
    var participants: [AgreementSignerSnapshot]
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
