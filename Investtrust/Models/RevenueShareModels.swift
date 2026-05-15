import FirebaseFirestore
import Foundation

// Equity deal repayment model. For equity deals, instead of fixed installments the seeker
// declares revenue each period and pays the investor's agreed percentage share.

// Lifecycle of one revenue-share period on the equity deal screen
enum RevenueSharePeriodStatus: String, Codable, Sendable, CaseIterable {
    case awaiting_declaration
    case awaiting_payment
    case awaiting_confirmation
    case confirmed_paid
    case disputed
}

// One row on the equity deal repayment screen — the seeker declares their revenue for this window
// and sends the investor's cut before the period is marked confirmed
struct RevenueSharePeriod: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(periodNo)" }
    var periodNo: Int
    var startDate: Date
    var endDate: Date
    var dueDate: Date
    var declaredRevenue: Double?         // seeker's reported revenue for this window
    var expectedShareAmount: Double?     // investor's cut (revenue × equity %)
    var actualPaidAmount: Double?        // what the seeker actually transferred
    var seekerDeclaredAt: Date?
    var seekerMarkedSentAt: Date?
    var investorMarkedReceivedAt: Date?
    var status: RevenueSharePeriodStatus
    var seekerProofImageURLs: [String]
    var investorProofImageURLs: [String]

    var proofImageURLs: [String] { seekerProofImageURLs + investorProofImageURLs }
}

extension RevenueSharePeriod {
    init?(firestoreMap m: [String: Any]) {
        let no = (m["periodNo"] as? Int) ?? (m["periodNo"] as? NSNumber)?.intValue
        guard let periodNo = no,
              let startDate = (m["startDate"] as? Timestamp)?.dateValue(),
              let endDate = (m["endDate"] as? Timestamp)?.dateValue(),
              let dueDate = (m["dueDate"] as? Timestamp)?.dateValue() else { return nil }
        let statusRaw = (m["status"] as? String) ?? RevenueSharePeriodStatus.awaiting_declaration.rawValue
        let status = RevenueSharePeriodStatus(rawValue: statusRaw.lowercased()) ?? .awaiting_declaration
        let declaredRevenue = Self.parseDouble(m["declaredRevenue"])
        let expectedShareAmount = Self.parseDouble(m["expectedShareAmount"])
        let actualPaidAmount = Self.parseDouble(m["actualPaidAmount"])
        let seekerDeclaredAt = (m["seekerDeclaredAt"] as? Timestamp)?.dateValue()
        let seekerMarkedSentAt = (m["seekerMarkedSentAt"] as? Timestamp)?.dateValue()
        let investorMarkedReceivedAt = (m["investorMarkedReceivedAt"] as? Timestamp)?.dateValue()
        let seekerProof = m["seekerProofImageURLs"] as? [String] ?? []
        let investorProof = m["investorProofImageURLs"] as? [String] ?? []
        let legacy = m["proofImageURLs"] as? [String] ?? []
        let finalSeekerProof = (seekerProof.isEmpty && investorProof.isEmpty) ? legacy : seekerProof
        self.init(
            periodNo: periodNo,
            startDate: startDate,
            endDate: endDate,
            dueDate: dueDate,
            declaredRevenue: declaredRevenue,
            expectedShareAmount: expectedShareAmount,
            actualPaidAmount: actualPaidAmount,
            seekerDeclaredAt: seekerDeclaredAt,
            seekerMarkedSentAt: seekerMarkedSentAt,
            investorMarkedReceivedAt: investorMarkedReceivedAt,
            status: status,
            seekerProofImageURLs: finalSeekerProof,
            investorProofImageURLs: investorProof
        )
    }

    func firestoreMap() -> [String: Any] {
        var o: [String: Any] = [
            "periodNo": periodNo,
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "dueDate": Timestamp(date: dueDate),
            "status": status.rawValue,
            "seekerProofImageURLs": seekerProofImageURLs,
            "investorProofImageURLs": investorProofImageURLs,
            "proofImageURLs": proofImageURLs
        ]
        if let declaredRevenue { o["declaredRevenue"] = declaredRevenue }
        if let expectedShareAmount { o["expectedShareAmount"] = expectedShareAmount }
        if let actualPaidAmount { o["actualPaidAmount"] = actualPaidAmount }
        if let seekerDeclaredAt { o["seekerDeclaredAt"] = Timestamp(date: seekerDeclaredAt) }
        if let seekerMarkedSentAt { o["seekerMarkedSentAt"] = Timestamp(date: seekerMarkedSentAt) }
        if let investorMarkedReceivedAt { o["investorMarkedReceivedAt"] = Timestamp(date: investorMarkedReceivedAt) }
        return o
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let v = value as? Double { return v }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}

// Generates the full list of revenue-share periods for an equity deal when the MOA goes active
enum RevenueShareScheduleGenerator {
    static func generatePeriods(
        startDate: Date,
        periodCount: Int,
        calendar: Calendar = .current
    ) -> [RevenueSharePeriod] {
        let n = max(1, periodCount)
        var rows: [RevenueSharePeriod] = []
        for i in 0..<n {
            let start = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate
            let end = calendar.date(byAdding: .month, value: i + 1, to: startDate) ?? start
            let due = end
            rows.append(
                RevenueSharePeriod(
                    periodNo: i + 1,
                    startDate: start,
                    endDate: end,
                    dueDate: due,
                    declaredRevenue: nil,
                    expectedShareAmount: nil,
                    actualPaidAmount: nil,
                    seekerDeclaredAt: nil,
                    seekerMarkedSentAt: nil,
                    investorMarkedReceivedAt: nil,
                    status: .awaiting_declaration,
                    seekerProofImageURLs: [],
                    investorProofImageURLs: []
                )
            )
        }
        return rows
    }
}
