import Foundation

struct InvestmentListing: Identifiable, Equatable, Hashable {
    let id: String
    let status: String
    let createdAt: Date?

    /// Firestore `opportunityId` (or nested `opportunity.id`) — used for seeker request management.
    let opportunityId: String?
    /// Investor who made the request.
    let investorId: String?
    /// Opportunity owner (seeker); stored for rules and accept validation.
    let seekerId: String?

    let opportunityTitle: String
    let imageURLs: [String]

    let investmentAmount: Double
    let finalInterestRate: Double?
    let finalTimelineMonths: Int?

    /// Copied from the opportunity when the request is created (for dashboards).
    let investmentType: InvestmentType

    /// Set when the seeker accepts the request.
    let acceptedAt: Date?

    /// Repayments received to date (optional; defaults to 0 when missing in Firestore).
    let receivedAmount: Double

    // MARK: - MOA / agreement

    let agreementStatus: AgreementStatus
    let signedByInvestorAt: Date?
    let signedBySeekerAt: Date?
    let agreementGeneratedAt: Date?
    /// Snapshot created when the seeker accepts (terms frozen for this deal).
    let agreement: InvestmentAgreementSnapshot?

    /// Generated when a **loan** agreement becomes fully signed (`agreementStatus == active`).
    let loanInstallments: [LoanInstallment]

    /// Final MOA PDF download URL after both parties sign (Cloudinary/Firebase).
    let moaPdfURL: String?

    /// SHA-256 hex of final signed PDF bytes (integrity).
    let moaContentHash: String?

    /// Signature PNG delivery URLs (Cloudinary HTTPS) after each party signs.
    let investorSignatureImageURL: String?
    let seekerSignatureImageURL: String?

    /// Seeker may edit/delete the opportunity only when **no** request is in a “blocking” state (see `nonBlockingStatusesForSeeker`).
    var blocksSeekerFromManagingOpportunity: Bool {
        let s = status.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return true }
        return !Self.nonBlockingStatusesForSeeker.contains(s)
    }

    /// Statuses that do **not** block the seeker (declined / withdrawn / cancelled).
    static let nonBlockingStatusesForSeeker: Set<String> = [
        "declined", "rejected", "cancelled", "withdrawn"
    ]

    var interestLabel: String {
        guard let finalInterestRate else { return "-" }
        return "\(finalInterestRate)%"
    }

    var timelineLabel: String {
        guard let finalTimelineMonths else { return "-" }
        return "\(finalTimelineMonths) months"
    }

    // MARK: - Display

    /// User-facing status line for list cards and detail (spec: pending / accepted / awaiting signatures / agreement active).
    var lifecycleDisplayTitle: String {
        if agreementStatus == .active {
            return "Agreement active"
        }
        if agreementStatus == .pending_signatures {
            return "Awaiting signatures"
        }
        let s = status.lowercased()
        switch s {
        case "pending":
            return "Waiting for seeker"
        case "accepted", "active":
            return "Accepted"
        case "completed":
            return "Completed"
        case "declined", "rejected":
            return "Declined"
        default:
            return status.capitalized
        }
    }

    func needsInvestorSignature(currentUserId: String?) -> Bool {
        guard agreementStatus == .pending_signatures else { return false }
        guard signedByInvestorAt == nil else { return false }
        guard let currentUserId, let iid = investorId else { return false }
        return currentUserId == iid
    }

    func needsSeekerSignature(currentUserId: String?) -> Bool {
        guard agreementStatus == .pending_signatures else { return false }
        guard signedBySeekerAt == nil else { return false }
        guard let currentUserId, let sid = seekerId else { return false }
        return currentUserId == sid
    }

    /// Sum of installments marked `confirmed_paid` (authoritative for loan repayments when present).
    var confirmedLoanRepaymentTotal: Double {
        loanInstallments
            .filter { $0.status == .confirmed_paid }
            .reduce(0) { $0 + $1.totalDue }
    }

    var isLoanWithSchedule: Bool {
        investmentType == .loan && !loanInstallments.isEmpty
    }

    /// Next installment that still needs action (by due date).
    var nextOpenLoanInstallment: LoanInstallment? {
        loanInstallments
            .filter { $0.status != .confirmed_paid }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }
}
