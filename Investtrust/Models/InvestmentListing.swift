import Foundation

enum EquityMilestoneStatus: String, Codable, Sendable, CaseIterable {
    case planned
    case in_progress
    case completed
}

struct EquityMilestoneProgress: Identifiable, Equatable, Hashable, Codable, Sendable {
    var id: String { title + "-" + (dueDate?.timeIntervalSince1970.description ?? "na") }
    let title: String
    let description: String
    let dueDate: Date?
    let status: EquityMilestoneStatus
    let updatedAt: Date?
    let note: String?
}

struct EquityVentureUpdate: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let message: String
    let ventureStage: String?
    let growthMetric: String?
    let attachmentURLs: [String]
    let createdAt: Date
}

struct InvestmentListing: Identifiable, Equatable, Hashable {
    let id: String
    let status: String
    let createdAt: Date?
    let updatedAt: Date?

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

    // MARK: - request / offer metadata

    let requestKind: InvestmentRequestKind
    let offerStatus: InvestmentOfferStatus
    let offerSource: InvestmentOfferSource?
    let offeredAmount: Double?
    let offeredInterestRate: Double?
    let offeredTimelineMonths: Int?
    let offerDescription: String?
    let offerChatId: String?
    let offerChatMessageId: String?

    // MARK: - MOA / agreement

    let agreementStatus: AgreementStatus
    let fundingStatus: FundingStatus
    let signedByInvestorAt: Date?
    let signedBySeekerAt: Date?
    let agreementGeneratedAt: Date?
    /// Snapshot created when the seeker accepts (terms frozen for this deal).
    let agreement: InvestmentAgreementSnapshot?

    /// Generated when a **loan** agreement becomes fully signed (`agreementStatus == active`).
    let loanInstallments: [LoanInstallment]
    /// Generated when a **revenue share** agreement becomes fully signed (`agreementStatus == active`).
    let revenueSharePeriods: [RevenueSharePeriod]

    /// Final MOA PDF download URL after both parties sign (Cloudinary/Firebase).
    let moaPdfURL: String?

    /// SHA-256 hex of final signed PDF bytes (integrity).
    let moaContentHash: String?

    /// Signature PNG delivery URLs (Cloudinary HTTPS) after each party signs.
    let investorSignatureImageURL: String?
    let seekerSignatureImageURL: String?
    let principalSentByInvestorAt: Date?
    let principalReceivedBySeekerAt: Date?
    let principalInvestorProofImageURLs: [String]
    let principalSeekerProofImageURLs: [String]
    /// Set when the seeker reports that the claimed principal transfer was not received; cleared when the investor marks sent again.
    let principalSeekerNotReceivedAt: Date?
    let principalSeekerNotReceivedReason: String?
    let equityMilestones: [EquityMilestoneProgress]
    let equityUpdates: [EquityVentureUpdate]

    init(
        id: String,
        status: String,
        createdAt: Date?,
        updatedAt: Date? = nil,
        opportunityId: String?,
        investorId: String?,
        seekerId: String?,
        opportunityTitle: String,
        imageURLs: [String],
        investmentAmount: Double,
        finalInterestRate: Double?,
        finalTimelineMonths: Int?,
        investmentType: InvestmentType,
        acceptedAt: Date?,
        receivedAmount: Double,
        requestKind: InvestmentRequestKind,
        offerStatus: InvestmentOfferStatus,
        offerSource: InvestmentOfferSource?,
        offeredAmount: Double?,
        offeredInterestRate: Double?,
        offeredTimelineMonths: Int?,
        offerDescription: String?,
        offerChatId: String?,
        offerChatMessageId: String?,
        agreementStatus: AgreementStatus,
        fundingStatus: FundingStatus,
        signedByInvestorAt: Date?,
        signedBySeekerAt: Date?,
        agreementGeneratedAt: Date?,
        agreement: InvestmentAgreementSnapshot?,
        loanInstallments: [LoanInstallment],
        revenueSharePeriods: [RevenueSharePeriod],
        moaPdfURL: String?,
        moaContentHash: String?,
        investorSignatureImageURL: String?,
        seekerSignatureImageURL: String?,
        principalSentByInvestorAt: Date?,
        principalReceivedBySeekerAt: Date?,
        principalInvestorProofImageURLs: [String],
        principalSeekerProofImageURLs: [String],
        principalSeekerNotReceivedAt: Date? = nil,
        principalSeekerNotReceivedReason: String? = nil,
        equityMilestones: [EquityMilestoneProgress] = [],
        equityUpdates: [EquityVentureUpdate] = []
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.opportunityId = opportunityId
        self.investorId = investorId
        self.seekerId = seekerId
        self.opportunityTitle = opportunityTitle
        self.imageURLs = imageURLs
        self.investmentAmount = investmentAmount
        self.finalInterestRate = finalInterestRate
        self.finalTimelineMonths = finalTimelineMonths
        self.investmentType = investmentType
        self.acceptedAt = acceptedAt
        self.receivedAmount = receivedAmount
        self.requestKind = requestKind
        self.offerStatus = offerStatus
        self.offerSource = offerSource
        self.offeredAmount = offeredAmount
        self.offeredInterestRate = offeredInterestRate
        self.offeredTimelineMonths = offeredTimelineMonths
        self.offerDescription = offerDescription
        self.offerChatId = offerChatId
        self.offerChatMessageId = offerChatMessageId
        self.agreementStatus = agreementStatus
        self.fundingStatus = fundingStatus
        self.signedByInvestorAt = signedByInvestorAt
        self.signedBySeekerAt = signedBySeekerAt
        self.agreementGeneratedAt = agreementGeneratedAt
        self.agreement = agreement
        self.loanInstallments = loanInstallments
        self.revenueSharePeriods = revenueSharePeriods
        self.moaPdfURL = moaPdfURL
        self.moaContentHash = moaContentHash
        self.investorSignatureImageURL = investorSignatureImageURL
        self.seekerSignatureImageURL = seekerSignatureImageURL
        self.principalSentByInvestorAt = principalSentByInvestorAt
        self.principalReceivedBySeekerAt = principalReceivedBySeekerAt
        self.principalInvestorProofImageURLs = principalInvestorProofImageURLs
        self.principalSeekerProofImageURLs = principalSeekerProofImageURLs
        self.principalSeekerNotReceivedAt = principalSeekerNotReceivedAt
        self.principalSeekerNotReceivedReason = principalSeekerNotReceivedReason
        self.equityMilestones = equityMilestones
        self.equityUpdates = equityUpdates
    }

    /// Seeker may edit/delete the opportunity only when **no** request is in a “blocking” state (see `nonBlockingStatusesForSeeker`).
    var blocksSeekerFromManagingOpportunity: Bool {
        let s = status.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return true }
        return !Self.nonBlockingStatusesForSeeker.contains(s)
    }

    /// Whether this row should contribute to the top “resolve requests / offers before editing” banner.
    /// In-flight deals (`agreementStatus == .active` or legacy `active` / `completed` status) are excluded — the copy is about pending requests, not ongoing investments.
    var triggersSeekerRequestResolutionBanner: Bool {
        guard blocksSeekerFromManagingOpportunity else { return false }
        if agreementStatus == .active { return false }
        let s = status.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s == "active" || s == "completed" { return false }
        return true
    }

    /// Statuses that do **not** block the seeker (declined / withdrawn / cancelled).
    static let nonBlockingStatusesForSeeker: Set<String> = [
        "declined", "rejected", "cancelled", "withdrawn"
    ]

    /// Canonical amount to display/use for deal math. Offers override legacy default snapshots.
    var effectiveAmount: Double {
        offeredAmount ?? investmentAmount
    }

    /// Canonical rate to display/use for deal math.
    var effectiveFinalInterestRate: Double? {
        offeredInterestRate ?? finalInterestRate ?? agreement?.termsSnapshot.interestRate
    }

    /// Canonical timeline to display/use for deal math.
    var effectiveFinalTimelineMonths: Int? {
        offeredTimelineMonths ?? finalTimelineMonths ?? agreement?.termsSnapshot.effectiveTimelineMonths
    }

    var interestLabel: String {
        let rate = effectiveFinalInterestRate
        guard let rate else { return "-" }
        return "\(rate)%"
    }

    var timelineLabel: String {
        let months = effectiveFinalTimelineMonths
        guard let months else { return "-" }
        return "\(months) months"
    }

    // MARK: - Display

    /// User-facing status line for list cards and detail (spec: pending / accepted / awaiting signatures / agreement active).
    var lifecycleDisplayTitle: String {
        let s = status.lowercased()
        if s == "completed" || fundingStatus == .closed {
            return "Agreement completed"
        }
        if agreementStatus == .active {
            return "Agreement active"
        }
        if agreementStatus == .pending_signatures {
            return "Awaiting signatures"
        }
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
        guard let currentUserId else { return false }
        if let agreement {
            return agreement.participants.contains {
                $0.signerId == currentUserId && $0.signerRole == .investor && !$0.isSigned
            }
        }
        // Legacy rows without embedded `agreement`: infer only once at least one party has signed.
        guard signedByInvestorAt != nil || signedBySeekerAt != nil else { return false }
        guard signedByInvestorAt == nil else { return false }
        guard let iid = investorId else { return false }
        return currentUserId == iid
    }

    func needsSeekerSignature(currentUserId: String?) -> Bool {
        guard agreementStatus == .pending_signatures else { return false }
        guard let currentUserId else { return false }
        if let agreement {
            return agreement.participants.contains {
                $0.signerId == currentUserId && $0.signerRole == .seeker && !$0.isSigned
            }
        }
        guard signedByInvestorAt != nil || signedBySeekerAt != nil else { return false }
        guard signedBySeekerAt == nil else { return false }
        guard let sid = seekerId else { return false }
        return currentUserId == sid
    }

    var agreementSignedCount: Int {
        guard let agreement else {
            return [signedByInvestorAt, signedBySeekerAt].compactMap(\.self).count
        }
        return agreement.participants.filter(\.isSigned).count
    }

    var agreementRequiredSignerCount: Int {
        agreement?.participants.count ?? 2
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

    /// Whether the loan repayment schedule and installment UI should be shown (not the pre-disbursement principal-only flow).
    /// Includes `.closed` because completed loans move from `disbursed` → `closed` while the schedule remains the source of truth for history.
    /// Includes `.defaulted` so parties can still see the schedule after default.
    var loanRepaymentsUnlocked: Bool {
        investmentType == .loan && [.disbursed, .closed, .defaulted].contains(fundingStatus)
    }

    var isOfferRequest: Bool {
        if requestKind == .offer_request { return true }
        if offeredAmount != nil || offeredInterestRate != nil || offeredTimelineMonths != nil { return true }
        if let offerDescription, !offerDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    var recencyDate: Date {
        updatedAt ?? createdAt ?? .distantPast
    }

    /// Next installment that still needs action (by due date).
    var nextOpenLoanInstallment: LoanInstallment? {
        loanInstallments
            .filter { $0.status != .confirmed_paid }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

}

extension InvestmentListing {
    /// Returns a copy with a different embedded `agreement` snapshot (same Firestore row id).
    func replacingAgreement(_ newAgreement: InvestmentAgreementSnapshot?) -> InvestmentListing {
        InvestmentListing(
            id: id,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            opportunityId: opportunityId,
            investorId: investorId,
            seekerId: seekerId,
            opportunityTitle: opportunityTitle,
            imageURLs: imageURLs,
            investmentAmount: investmentAmount,
            finalInterestRate: finalInterestRate,
            finalTimelineMonths: finalTimelineMonths,
            investmentType: investmentType,
            acceptedAt: acceptedAt,
            receivedAmount: receivedAmount,
            requestKind: requestKind,
            offerStatus: offerStatus,
            offerSource: offerSource,
            offeredAmount: offeredAmount,
            offeredInterestRate: offeredInterestRate,
            offeredTimelineMonths: offeredTimelineMonths,
            offerDescription: offerDescription,
            offerChatId: offerChatId,
            offerChatMessageId: offerChatMessageId,
            agreementStatus: agreementStatus,
            fundingStatus: fundingStatus,
            signedByInvestorAt: signedByInvestorAt,
            signedBySeekerAt: signedBySeekerAt,
            agreementGeneratedAt: agreementGeneratedAt,
            agreement: newAgreement,
            loanInstallments: loanInstallments,
            revenueSharePeriods: revenueSharePeriods,
            moaPdfURL: moaPdfURL,
            moaContentHash: moaContentHash,
            investorSignatureImageURL: investorSignatureImageURL,
            seekerSignatureImageURL: seekerSignatureImageURL,
            principalSentByInvestorAt: principalSentByInvestorAt,
            principalReceivedBySeekerAt: principalReceivedBySeekerAt,
            principalInvestorProofImageURLs: principalInvestorProofImageURLs,
            principalSeekerProofImageURLs: principalSeekerProofImageURLs,
            principalSeekerNotReceivedAt: principalSeekerNotReceivedAt,
            principalSeekerNotReceivedReason: principalSeekerNotReceivedReason,
            equityMilestones: equityMilestones,
            equityUpdates: equityUpdates
        )
    }

    /// Some write paths attach `agreement` only to one linked `investments` row. The seeker can read all rows
    /// for an opportunity — copy the snapshot so review/sign UI matches `signAgreement`’s server-side fallback.
    func withAgreementHydrated(fromSiblingRows rows: [InvestmentListing]) -> InvestmentListing {
        guard agreement == nil else { return self }
        guard let oid = opportunityId, !oid.isEmpty else { return self }
        guard let snap = rows.lazy.first(where: { row in
            guard let a = row.agreement else { return false }
            return a.agreementId == oid || row.id == id
        })?.agreement else {
            return self
        }
        return replacingAgreement(snap)
    }
}
