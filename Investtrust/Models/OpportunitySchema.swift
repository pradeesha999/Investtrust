import FirebaseFirestore
import Foundation

// Core enums and schema helpers for opportunity listings.
// Defines investment types, repayment options, risk levels, and Firestore encoding/decoding.

// The two deal types the seeker can choose when creating an opportunity
enum InvestmentType: String, CaseIterable, Codable, Sendable {
    case loan
    case equity

    var displayName: String {
        switch self {
        case .loan: return "Loan"
        case .equity: return "Equity"
        }
    }

    static func parse(_ raw: String?) -> InvestmentType {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return .loan
        }
        return InvestmentType(rawValue: raw) ?? .loan
    }
}

enum RepaymentFrequency: String, CaseIterable, Codable, Sendable {
    case monthly
    case weekly
    case one_time  // full principal + interest paid in one lump sum at maturity

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        case .one_time: return "One-time at maturity"
        }
    }
}

enum RiskLevel: String, CaseIterable, Codable, Sendable {
    case low
    case medium
    case high

    var displayName: String {
        rawValue.capitalized
    }

    static func parse(_ raw: String?) -> RiskLevel {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return .medium
        }
        return RiskLevel(rawValue: raw) ?? .medium
    }
}

enum VerificationStatus: String, CaseIterable, Codable, Sendable {
    case unverified
    case verified

    static func parse(_ raw: String?) -> VerificationStatus {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return .unverified
        }
        return VerificationStatus(rawValue: raw) ?? .unverified
    }
}

enum ExpectedReturnType: String, CaseIterable, Codable, Sendable {
    case fixed
    case product
    case none
}

enum EquityRoiTimeline: String, CaseIterable, Codable, Sendable {
    case six_months
    case one_year
    case two_years
    case five_years

    var displayName: String {
        switch self {
        case .six_months: return "6 Months"
        case .one_year: return "1 Year"
        case .two_years: return "2 Years"
        case .five_years: return "5 Years"
        }
    }

    var months: Int {
        switch self {
        case .six_months: return 6
        case .one_year: return 12
        case .two_years: return 24
        case .five_years: return 60
        }
    }
}

enum VentureStage: String, CaseIterable, Codable, Sendable {
    case idea_stage
    case prototype
    case beta_launch
    case early_users
    case revenue_generating
    case scaling
}

// Milestone

struct OpportunityMilestone: Equatable, Hashable, Codable, Sendable {
    var title: String
    var description: String
    // Legacy: calendar target from older listings (creation-based).
    var expectedDate: Date?
    // Days after investment acceptance this milestone is due (preferred).
    var dueDaysAfterAcceptance: Int?
}

// Terms (stored under `terms` in Firestore)

struct OpportunityTerms: Equatable, Hashable, Codable, Sendable {
    var interestRate: Double?
    var repaymentTimelineMonths: Int?
    var repaymentFrequency: RepaymentFrequency?
    var equityPercentage: Double?
    var businessValuation: Double?
    var equityTimelineMonths: Int?
    var ventureName: String?
    var ventureStage: VentureStage?
    var futureGoals: String?
    var revenueModel: String?
    var targetAudience: String?
    var demoLinks: String?
    var equityRoiTimeline: EquityRoiTimeline?
    var exitPlan: String?
    var revenueSharePercent: Double?
    var targetReturnAmount: Double?
    var maxDurationMonths: Int?
    var expectedReturnType: ExpectedReturnType?
    var expectedReturnValue: String?
    var completionDate: Date?
    var customTermsSummary: String?

    static let empty = OpportunityTerms()

    var effectiveInterestRate: Double { interestRate ?? 0 }

    var effectiveTimelineMonths: Int {
        max(1, repaymentTimelineMonths ?? maxDurationMonths ?? equityTimelineMonths ?? 1)
    }
}

// Firestore encode/decode

enum OpportunityFirestoreCoding {
    static func termsDictionary(from t: OpportunityTerms, type: InvestmentType) -> [String: Any] {
        var m: [String: Any] = [:]
        switch type {
        case .loan:
            if let v = t.interestRate { m["interestRate"] = v }
            if let v = t.repaymentTimelineMonths { m["repaymentTimelineMonths"] = v }
            if let v = t.repaymentFrequency { m["repaymentFrequency"] = v.rawValue }
        case .equity:
            if let v = t.equityPercentage { m["equityPercentage"] = v }
            if let v = t.businessValuation { m["businessValuation"] = v }
            if let v = t.equityTimelineMonths { m["equityTimelineMonths"] = v }
            if let v = t.ventureName { m["ventureName"] = v }
            if let v = t.ventureStage { m["ventureStage"] = v.rawValue }
            if let v = t.futureGoals { m["futureGoals"] = v }
            if let v = t.revenueModel { m["revenueModel"] = v }
            if let v = t.targetAudience { m["targetAudience"] = v }
            if let v = t.demoLinks { m["demoLinks"] = v }
            if let v = t.equityRoiTimeline { m["equityRoiTimeline"] = v.rawValue }
            if let v = t.exitPlan { m["exitPlan"] = v }
        }
        return m
    }

    static func parseTerms(from data: [String: Any], type: InvestmentType) -> OpportunityTerms {
        let nested = (data["terms"] as? [String: Any]) ?? [:]

        func dbl(_ key: String) -> Double? {
            if let v = nested[key] as? Double { return v }
            if let n = nested[key] as? NSNumber { return n.doubleValue }
            if let i = nested[key] as? Int { return Double(i) }
            if let i = nested[key] as? Int64 { return Double(i) }
            if let v = data[key] as? Double { return v }
            if let n = data[key] as? NSNumber { return n.doubleValue }
            if let i = data[key] as? Int { return Double(i) }
            if let i = data[key] as? Int64 { return Double(i) }
            return nil
        }
        func intg(_ key: String) -> Int? {
            if let v = nested[key] as? Int { return v }
            if let n = nested[key] as? NSNumber { return n.intValue }
            if let v = nested[key] as? Int64 { return Int(v) }
            if let v = data[key] as? Int { return v }
            if let n = data[key] as? NSNumber { return n.intValue }
            if let v = data[key] as? Int64 { return Int(v) }
            return nil
        }
        func str(_ key: String) -> String? {
            let a = (nested[key] as? String) ?? (data[key] as? String)
            let t = a?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        func date(_ key: String) -> Date? {
            if let ts = nested[key] as? Timestamp { return ts.dateValue() }
            if let ts = data[key] as? Timestamp { return ts.dateValue() }
            return nil
        }

        var t = OpportunityTerms()
        switch type {
        case .loan:
            t.interestRate = dbl("interestRate")
            t.repaymentTimelineMonths = intg("repaymentTimelineMonths")
            if let raw = nested["repaymentFrequency"] as? String ?? data["repaymentFrequency"] as? String {
                t.repaymentFrequency = RepaymentFrequency(rawValue: raw.lowercased())
            }
        case .equity:
            t.equityPercentage = dbl("equityPercentage")
            t.businessValuation = dbl("businessValuation")
            t.equityTimelineMonths = intg("equityTimelineMonths")
            t.ventureName = str("ventureName")
            if let raw = (nested["ventureStage"] as? String) ?? (data["ventureStage"] as? String) {
                t.ventureStage = VentureStage(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
            t.futureGoals = str("futureGoals")
            t.revenueModel = str("revenueModel")
            t.targetAudience = str("targetAudience")
            t.demoLinks = str("demoLinks")
            if let raw = (nested["equityRoiTimeline"] as? String) ?? (data["equityRoiTimeline"] as? String) {
                t.equityRoiTimeline = EquityRoiTimeline(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
            t.exitPlan = str("exitPlan")
        }
        return t
    }

    static func milestones(from data: [String: Any]) -> [OpportunityMilestone] {
        guard let arr = data["milestones"] as? [[String: Any]] else { return [] }
        let parsed = arr.compactMap { row -> OpportunityMilestone? in
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let desc = (row["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let expected: Date? = {
                if let ts = row["expectedDate"] as? Timestamp { return ts.dateValue() }
                return nil
            }()
            let daysAfter: Int? = {
                if let v = row["daysAfterAcceptance"] as? Int { return v >= 0 ? v : nil }
                if let n = row["daysAfterAcceptance"] as? NSNumber { let i = n.intValue; return i >= 0 ? i : nil }
                if let v = row["dueDaysAfterAcceptance"] as? Int { return v >= 0 ? v : nil }
                if let n = row["dueDaysAfterAcceptance"] as? NSNumber { let i = n.intValue; return i >= 0 ? i : nil }
                return nil
            }()
            if title.isEmpty && desc.isEmpty { return nil }
            return OpportunityMilestone(
                title: title.isEmpty ? "Milestone" : title,
                description: desc,
                expectedDate: expected,
                dueDaysAfterAcceptance: daysAfter
            )
        }
        return Self.sortedMilestonesChronologically(parsed)
    }

    // Earliest `daysAfterAcceptance` first; then legacy `expectedDate`; undated last (stable by title).
    static func sortedMilestonesChronologically(_ items: [OpportunityMilestone]) -> [OpportunityMilestone] {
        items.sorted { a, b in
            func tierAndSortValue(_ m: OpportunityMilestone) -> (Int, Double, String) {
                if let d = m.dueDaysAfterAcceptance {
                    return (0, Double(d), m.title)
                }
                if let e = m.expectedDate {
                    return (1, e.timeIntervalSince1970, m.title)
                }
                return (2, 0, m.title)
            }
            let ka = tierAndSortValue(a)
            let kb = tierAndSortValue(b)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return ka.2.localizedCaseInsensitiveCompare(kb.2) == .orderedAscending
        }
    }

    static func milestonesPayload(_ items: [OpportunityMilestone]) -> [[String: Any]] {
        items.map { m in
            var o: [String: Any] = [
                "title": m.title,
                "description": m.description
            ]
            if let d = m.expectedDate {
                o["expectedDate"] = Timestamp(date: d)
            }
            if let days = m.dueDaysAfterAcceptance, days >= 0 {
                o["daysAfterAcceptance"] = days
            }
            return o
        }
    }
}
