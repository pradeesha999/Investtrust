import Foundation

// Tracks where the MOA (Memorandum of Agreement) signing process stands on a deal
enum AgreementStatus: String, Codable, Sendable, CaseIterable {
    case none               // no agreement yet
    case pending_signatures // seeker accepted; waiting for both parties to sign
    case active             // both sides signed — deal is live
}

// Tracks loan disbursement and repayment lifecycle after the MOA is signed
enum FundingStatus: String, Codable, Sendable, CaseIterable {
    case none
    case awaiting_disbursement  // seeker confirmed receipt; investor yet to transfer funds
    case disbursed              // investor confirmed the transfer
    case defaulted              // seeker missed payments
    case closed                 // fully repaid
}

// Whether the investor used the listing defaults or submitted a custom offer
enum InvestmentRequestKind: String, Codable, Sendable, CaseIterable {
    case default_request  // investor clicked "Invest" with no changes
    case offer_request    // investor proposed custom amount, rate, or term
}

// Lifecycle state of a counter-offer in the `offers` collection
enum InvestmentOfferStatus: String, Codable, Sendable, CaseIterable {
    case pending     // seeker hasn't responded yet
    case accepted
    case declined
    case superseded  // replaced by a newer offer for the same deal
}

// Where the offer originated — used for analytics and display labels
enum InvestmentOfferSource: String, Codable, Sendable, CaseIterable {
    case chat          // sent from the chat room
    case detail_sheet  // sent from the opportunity detail sheet
}

// Which side of the deal this participant represents in the MOA
enum AgreementSignerRole: String, Codable, Sendable, CaseIterable {
    case seeker
    case investor
}

// Records one participant's signature status in the MOA snapshot
struct AgreementSignerSnapshot: Equatable, Hashable, Sendable, Codable {
    var signerId: String
    var signerRole: AgreementSignerRole
    var displayName: String
    var signatureURL: String?   // Cloudinary URL of the drawn signature image
    var signedAt: Date?

    // True only when both the timestamp and the signature image URL are present
    var isSigned: Bool {
        signedAt != nil && !(signatureURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// The full MOA data frozen at the moment the seeker accepts an investment.
// Stored on the investment document so the PDF can always be regenerated from this snapshot.
struct InvestmentAgreementSnapshot: Equatable, Hashable, Sendable {
    var agreementId: String          // typically the opportunityId
    var agreementVersion: Int        // bumped when the MOA template changes
    var termsSnapshotHash: String    // hash of the frozen deal terms for integrity checks
    var requiredSignerIds: [String]  // user IDs who must sign before the deal goes active
    var linkedInvestmentIds: [String] // all investment docs sharing this MOA
    var participants: [AgreementSignerSnapshot]
    var opportunityTitle: String
    var investorName: String
    var seekerName: String
    var investmentAmount: Double
    var investmentType: InvestmentType
    var termsSnapshot: OpportunityTerms  // frozen deal economics (rate, term, etc.)
    var createdAt: Date

    // Repayment schedule cadence derived from the frozen terms (monthly by default for loans)
    var loanRepaymentPlan: LoanRepaymentPlan {
        guard investmentType == .loan else { return .monthly }
        return LoanRepaymentPlan.from(termsSnapshot.repaymentFrequency)
    }
}
