import FirebaseFirestore
import Foundation

// A counter-offer row stored in the `offers` Firestore collection.
// Created when an investor proposes custom terms (amount/rate/term) instead of accepting listing defaults.
struct FirestoreInvestorOffer: Equatable, Sendable, Identifiable {
    let id: String
    let investmentId: String
    let opportunityId: String
    let investorId: String
    let seekerId: String
    let amount: Double
    let interestRate: Double
    let timelineMonths: Int
    let description: String?
    let source: String?
    let status: String
    let createdAt: Date?
    let updatedAt: Date?

    init?(id: String, data: [String: Any]) {
        let investmentId = (data["investmentId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let opportunityId = (data["opportunityId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let investorId = (data["investorId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let seekerId = (data["seekerId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !investmentId.isEmpty, !opportunityId.isEmpty, !investorId.isEmpty, !seekerId.isEmpty else {
            return nil
        }
        guard let amount = Self.parseDouble(data["amount"]), amount > 0 else { return nil }
        let interestRate = Self.parseDouble(data["interestRate"]) ?? 0
        guard let timelineMonths = Self.parseInt(data["timelineMonths"]), timelineMonths > 0 else {
            return nil
        }
        let description = (data["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (data["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = ((data["status"] as? String) ?? "pending")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        self.id = id
        self.investmentId = investmentId
        self.opportunityId = opportunityId
        self.investorId = investorId
        self.seekerId = seekerId
        self.amount = amount
        self.interestRate = interestRate
        self.timelineMonths = timelineMonths
        self.description = description?.isEmpty == false ? description : nil
        self.source = source?.isEmpty == false ? source : nil
        self.status = status
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
    }

    // Builds the Firestore write payload for a new offer document
    static func creationPayload(
        investmentId: String,
        opportunityId: String,
        investorId: String,
        seekerId: String,
        amount: Double,
        interestRate: Double,
        timelineMonths: Int,
        description: String,
        source: String,
        status: String,
        now: Date
    ) -> [String: Any] {
        let ts = Timestamp(date: now)
        return [
            "investmentId": investmentId,
            "opportunityId": opportunityId,
            "investorId": investorId,
            "seekerId": seekerId,
            "amount": amount,
            "interestRate": interestRate,
            "timelineMonths": timelineMonths,
            "description": description,
            "source": source,
            "status": status,
            "createdAt": ts,
            "updatedAt": ts
        ]
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let v = value as? Double { return v }
        if let n = value as? NSNumber { return n.doubleValue }
        if let v = value as? Int { return Double(v) }
        if let v = value as? Int64 { return Double(v) }
        if let s = value as? String {
            let cleaned = s.replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }
        return nil
    }

    private static func parseInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String {
            let digits = s.filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }
}
