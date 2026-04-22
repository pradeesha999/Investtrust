import FirebaseFirestore
import Foundation

// MARK: - Enums

enum InvestmentType: String, CaseIterable, Codable, Sendable {
    case loan
    case equity
    case revenue_share
    case project
    case custom

    var displayName: String {
        switch self {
        case .loan: return "Loan"
        case .equity: return "Equity"
        case .revenue_share: return "Revenue share"
        case .project: return "Project"
        case .custom: return "Custom"
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
    /// Single payment at end of term (full principal + simple interest).
    case one_time

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

// MARK: - Milestone

struct OpportunityMilestone: Equatable, Hashable, Codable, Sendable {
    var title: String
    var description: String
    var expectedDate: Date?
}

// MARK: - Terms (stored under `terms` in Firestore)

struct OpportunityTerms: Equatable, Hashable, Codable, Sendable {
    var interestRate: Double?
    var repaymentTimelineMonths: Int?
    var repaymentFrequency: RepaymentFrequency?
    var equityPercentage: Double?
    var businessValuation: Double?
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
        max(1, repaymentTimelineMonths ?? maxDurationMonths ?? 1)
    }
}

// MARK: - Firestore encode/decode

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
            if let v = t.exitPlan { m["exitPlan"] = v }
        case .revenue_share:
            if let v = t.revenueSharePercent { m["revenueSharePercent"] = v }
            if let v = t.targetReturnAmount { m["targetReturnAmount"] = v }
            if let v = t.maxDurationMonths { m["maxDurationMonths"] = v }
        case .project:
            if let v = t.expectedReturnType { m["expectedReturnType"] = v.rawValue }
            if let v = t.expectedReturnValue { m["expectedReturnValue"] = v }
            if let d = t.completionDate { m["completionDate"] = Timestamp(date: d) }
        case .custom:
            if let v = t.customTermsSummary { m["customTermsSummary"] = v }
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
            t.exitPlan = str("exitPlan")
        case .revenue_share:
            t.revenueSharePercent = dbl("revenueSharePercent")
            t.targetReturnAmount = dbl("targetReturnAmount")
            t.maxDurationMonths = intg("maxDurationMonths")
        case .project:
            if let raw = nested["expectedReturnType"] as? String ?? data["expectedReturnType"] as? String {
                t.expectedReturnType = ExpectedReturnType(rawValue: raw.lowercased())
            }
            t.expectedReturnValue = str("expectedReturnValue")
            t.completionDate = date("completionDate")
        case .custom:
            t.customTermsSummary = str("customTermsSummary")
        }
        return t
    }

    static func milestones(from data: [String: Any]) -> [OpportunityMilestone] {
        guard let arr = data["milestones"] as? [[String: Any]] else { return [] }
        return arr.compactMap { row -> OpportunityMilestone? in
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let desc = (row["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let expected: Date? = {
                if let ts = row["expectedDate"] as? Timestamp { return ts.dateValue() }
                return nil
            }()
            if title.isEmpty && desc.isEmpty { return nil }
            return OpportunityMilestone(title: title.isEmpty ? "Milestone" : title, description: desc, expectedDate: expected)
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
            return o
        }
    }
}
