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
    let milestones: [OpportunityMilestone]
    let location: String
    let riskLevel: RiskLevel
    let verificationStatus: VerificationStatus
    let documentURLs: [String]

    let status: String
    let createdAt: Date?

    let imageStoragePaths: [String]
    let videoStoragePath: String?
    let videoURL: String?
    let mediaWarnings: [String]
    let imagePublicIds: [String]
    let videoPublicId: String?

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

    var repaymentLabel: String {
        switch investmentType {
        case .loan:
            if let m = terms.repaymentTimelineMonths {
                return "\(m) months"
            }
            return "\(terms.effectiveTimelineMonths) months"
        case .revenue_share:
            if let m = terms.maxDurationMonths {
                return "\(m) months max"
            }
            return "—"
        case .equity:
            if let p = terms.equityPercentage {
                return String(format: "%.1f%% equity", p)
            }
            return "Equity"
        case .project:
            return terms.completionDate.map { Self.shortDate($0) } ?? "—"
        case .custom:
            return "Custom terms"
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
            return parts.isEmpty ? "Equity" : parts.joined(separator: " · ")
        case .revenue_share:
            var parts: [String] = []
            if let e = terms.revenueSharePercent { parts.append("\(formatRate(e))% rev.") }
            if let t = terms.targetReturnAmount { parts.append("Target LKR \(Int(t))") }
            return parts.isEmpty ? "Revenue share" : parts.joined(separator: " · ")
        case .project:
            let kind = terms.expectedReturnType?.rawValue ?? "—"
            let val = terms.expectedReturnValue ?? "—"
            return "\(kind): \(val)"
        case .custom:
            return "Custom"
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
