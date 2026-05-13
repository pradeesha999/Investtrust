import Foundation

struct OpportunityListing: Identifiable, Equatable, Hashable {
    let id: String
    let ownerId: String
    let title: String
    let category: String
    let description: String

    let investmentType: InvestmentType
    let amountRequested: Double
    let minimumInvestment: Double
    let maximumInvestors: Int?

    /// Type-specific fields (loan, equity, …) — also see top-level legacy keys in Firestore.
    let terms: OpportunityTerms

    let useOfFunds: String
    /// How the business generates income to service the deal (seeker narrative).
    let incomeGenerationMethod: String
    let milestones: [OpportunityMilestone]
    let location: String
    let riskLevel: RiskLevel
    let verificationStatus: VerificationStatus
    /// Optional analytics counter from backend.
    let viewCount: Int?
    /// If false, investor cannot submit negotiated offer terms.
    let isNegotiable: Bool
    let documentURLs: [String]

    let status: String
    let createdAt: Date?

    let imageStoragePaths: [String]
    let videoStoragePath: String?
    let videoURL: String?
    let mediaWarnings: [String]
    let imagePublicIds: [String]
    let videoPublicId: String?

    init(
        id: String,
        ownerId: String,
        title: String,
        category: String,
        description: String,
        investmentType: InvestmentType,
        amountRequested: Double,
        minimumInvestment: Double,
        maximumInvestors: Int?,
        terms: OpportunityTerms,
        useOfFunds: String,
        incomeGenerationMethod: String,
        milestones: [OpportunityMilestone],
        location: String,
        riskLevel: RiskLevel,
        verificationStatus: VerificationStatus,
        viewCount: Int? = nil,
        isNegotiable: Bool,
        documentURLs: [String],
        status: String,
        createdAt: Date?,
        imageStoragePaths: [String],
        videoStoragePath: String?,
        videoURL: String?,
        mediaWarnings: [String],
        imagePublicIds: [String],
        videoPublicId: String?
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.category = category
        self.description = description
        self.investmentType = investmentType
        self.amountRequested = amountRequested
        self.minimumInvestment = minimumInvestment
        self.maximumInvestors = maximumInvestors
        self.terms = terms
        self.useOfFunds = useOfFunds
        self.incomeGenerationMethod = incomeGenerationMethod
        self.milestones = milestones
        self.location = location
        self.riskLevel = riskLevel
        self.verificationStatus = verificationStatus
        self.viewCount = viewCount
        self.isNegotiable = isNegotiable
        self.documentURLs = documentURLs
        self.status = status
        self.createdAt = createdAt
        self.imageStoragePaths = imageStoragePaths
        self.videoStoragePath = videoStoragePath
        self.videoURL = videoURL
        self.mediaWarnings = mediaWarnings
        self.imagePublicIds = imagePublicIds
        self.videoPublicId = videoPublicId
    }

    // MARK: - Legacy compatibility (loan metrics)

    /// Loan interest %; for other types typically 0 — use `terms` for full detail.
    var interestRate: Double {
        terms.effectiveInterestRate
    }

    /// Primary timeline in months (loan repayment, revenue-share max, or 1).
    var repaymentTimelineMonths: Int {
        terms.effectiveTimelineMonths
    }

    var effectiveVideoReference: String? {
        let u = videoURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u, !u.isEmpty { return u }
        let p = videoStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p, !p.isEmpty { return p }
        return nil
    }

    var formattedAmountLKR: String {
        let n = NSNumber(value: amountRequested)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", amountRequested)
    }

    var formattedMinimumLKR: String {
        let n = NSNumber(value: minimumInvestment)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", minimumInvestment)
    }

    /// Firestore `status` normalized for comparisons (blank values are treated as open listings).
    var normalizedListingStatus: String {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.isEmpty ? "open" : s
    }

    var isOpenForInvesting: Bool {
        normalizedListingStatus == "open"
    }

    var repaymentLabel: String {
        switch investmentType {
        case .loan:
            if let m = terms.repaymentTimelineMonths {
                return "\(m) months"
            }
            return "\(terms.effectiveTimelineMonths) months"
        case .equity:
            if let roi = terms.equityRoiTimeline {
                return roi.displayName + " ROI"
            }
            if let p = terms.equityPercentage {
                return String(format: "%.1f%% equity", p)
            }
            return "Equity"
        }
    }

    var termsSummaryLine: String {
        switch investmentType {
        case .loan:
            if let r = terms.interestRate, let m = terms.repaymentTimelineMonths {
                let freq = terms.repaymentFrequency?.rawValue ?? "monthly"
                return "\(formatRate(r))% · \(m) mo · \(freq)"
            }
            return "Loan"
        case .equity:
            var parts: [String] = []
            if let e = terms.equityPercentage { parts.append(String(format: "%.1f%% equity", e)) }
            if let v = terms.businessValuation { parts.append("Val. LKR \(Int(v))") }
            if let roi = terms.equityRoiTimeline { parts.append(roi.displayName + " ROI") }
            return parts.isEmpty ? "Equity" : parts.joined(separator: " · ")
        }
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) { return String(Int(rate)) }
        return String(rate)
    }
}

// MARK: - Seeker UI: show agreed deal economics

extension OpportunityListing {
    /// Matches `OpportunityService`’s per-slot ticket sizing (equal split when `maximumInvestors` > 1).
    static func listingMinimumTicket(amountRequested: Double, maximumInvestors: Int?) -> Double {
        let cap = max(1, maximumInvestors ?? 1)
        guard amountRequested > 0 else { return 0 }
        if cap > 1 {
            let raw = amountRequested / Double(cap)
            return (raw * 100).rounded() / 100
        }
        return amountRequested
    }

    /// Picks the investment row whose economics should represent the listing after acceptance / while ongoing.
    static func primarySeekerDisplayInvestment(rowsForSameOpportunity: [InvestmentListing]) -> InvestmentListing? {
        let candidates = rowsForSameOpportunity.filter { inv in
            let s = inv.status.lowercased()
            if ["accepted", "active", "completed"].contains(s) { return true }
            if inv.acceptedAt != nil { return true }
            if inv.agreementStatus == .pending_signatures || inv.agreementStatus == .active { return true }
            return false
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { a, b in
            let da = a.acceptedAt ?? a.updatedAt ?? a.createdAt ?? .distantPast
            let db = b.acceptedAt ?? b.updatedAt ?? b.createdAt ?? .distantPast
            return da < db
        }
    }

    /// Builds a listing snapshot using the **accepted** investment’s amount / rate / months so seeker UI
    /// matches the agreed deal even when the `opportunities` document is still on pre-offer defaults.
    func withSeekerAcceptedEconomics(from inv: InvestmentListing) -> OpportunityListing {
        let amt = inv.effectiveAmount
        guard amt > 0 else { return self }
        var t = terms
        switch investmentType {
        case .loan:
            if let r = inv.effectiveFinalInterestRate { t.interestRate = r }
            if let m = inv.effectiveFinalTimelineMonths { t.repaymentTimelineMonths = m }
        case .equity:
            if let r = inv.effectiveFinalInterestRate { t.equityPercentage = r }
            if let m = inv.effectiveFinalTimelineMonths { t.equityTimelineMonths = m }
        }
        let minInv = Self.listingMinimumTicket(amountRequested: amt, maximumInvestors: maximumInvestors)
        let resolvedMin = minInv > 0 ? minInv : minimumInvestment
        return OpportunityListing(
            id: id,
            ownerId: ownerId,
            title: title,
            category: category,
            description: description,
            investmentType: investmentType,
            amountRequested: amt,
            minimumInvestment: resolvedMin,
            maximumInvestors: maximumInvestors,
            terms: t,
            useOfFunds: useOfFunds,
            incomeGenerationMethod: incomeGenerationMethod,
            milestones: milestones,
            location: location,
            riskLevel: riskLevel,
            verificationStatus: verificationStatus,
            viewCount: viewCount,
            isNegotiable: isNegotiable,
            documentURLs: documentURLs,
            status: status,
            createdAt: createdAt,
            imageStoragePaths: imageStoragePaths,
            videoStoragePath: videoStoragePath,
            videoURL: videoURL,
            mediaWarnings: mediaWarnings,
            imagePublicIds: imagePublicIds,
            videoPublicId: videoPublicId
        )
    }

    func overlayingAcceptedIfPresent(investments: [InvestmentListing]) -> OpportunityListing {
        let rows = investments.filter { $0.opportunityId == id }
        guard let inv = Self.primarySeekerDisplayInvestment(rowsForSameOpportunity: rows) else { return self }
        return withSeekerAcceptedEconomics(from: inv)
    }
}
