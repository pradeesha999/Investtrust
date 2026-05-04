import FirebaseFirestore
import Foundation

/// Loan repayment cadence (mirrors `RepaymentFrequency` for opportunities plus explicit naming in services).
enum LoanRepaymentPlan: String, CaseIterable, Codable, Sendable {
    case monthly
    case weekly
    case one_time

    static func parse(_ raw: String?) -> LoanRepaymentPlan {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if s == RepaymentFrequency.monthly.rawValue { return .monthly }
        if s == RepaymentFrequency.weekly.rawValue { return .weekly }
        if s == RepaymentFrequency.one_time.rawValue || s == "onetime" { return .one_time }
        return .monthly
    }

    static func from(_ frequency: RepaymentFrequency?) -> LoanRepaymentPlan {
        switch frequency {
        case .monthly?: return .monthly
        case .weekly?: return .weekly
        case .one_time?: return .one_time
        case nil: return .monthly
        }
    }

    var firestoreValue: String { rawValue }
}

/// Per-installment state for dual-confirmation repayment tracking.
enum LoanInstallmentStatus: String, Codable, Sendable, CaseIterable {
    case scheduled
    case awaiting_confirmation
    case confirmed_paid
    case disputed
}

/// One row in the frozen loan schedule (Firestore maps under `loanInstallments`).
struct LoanInstallment: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(installmentNo)" }
    var installmentNo: Int
    var dueDate: Date
    var principalComponent: Double
    var interestComponent: Double
    var totalDue: Double
    var status: LoanInstallmentStatus
    /// Investor acknowledges **receiving** this repayment (funds arrived).
    var investorMarkedPaidAt: Date?
    /// Seeker acknowledges **sending** this repayment (after attaching payment proof).
    var seekerMarkedReceivedAt: Date?
    /// Payment slip / transfer proof uploaded by the seeker.
    var seekerProofImageURLs: [String]
    /// Optional receipt or cash-deposit proof uploaded by the investor.
    var investorProofImageURLs: [String]

    /// Combined list (seeker first, then investor). Matches legacy `proofImageURLs` in Firestore when not split.
    var proofImageURLs: [String] { seekerProofImageURLs + investorProofImageURLs }

    var isFullyConfirmed: Bool {
        investorMarkedPaidAt != nil && seekerMarkedReceivedAt != nil
    }
}

// MARK: - Firestore

extension LoanInstallment {
    init?(firestoreMap m: [String: Any]) {
        let no = (m["installmentNo"] as? Int) ?? (m["installmentNo"] as? NSNumber)?.intValue
        guard let installmentNo = no,
              let dueDate = (m["dueDate"] as? Timestamp)?.dateValue() else { return nil }
        let principal = Self.parseDouble(m["principalComponent"]) ?? 0
        let interest = Self.parseDouble(m["interestComponent"]) ?? 0
        let total = Self.parseDouble(m["totalDue"]) ?? (principal + interest)
        let statusRaw = (m["status"] as? String) ?? LoanInstallmentStatus.scheduled.rawValue
        let status = LoanInstallmentStatus(rawValue: statusRaw.lowercased()) ?? .scheduled
        let invPaid = (m["investorMarkedPaidAt"] as? Timestamp)?.dateValue()
        let seekRec = (m["seekerMarkedReceivedAt"] as? Timestamp)?.dateValue()
        let seekerP = m["seekerProofImageURLs"] as? [String] ?? []
        let investorP = m["investorProofImageURLs"] as? [String] ?? []
        let legacy = m["proofImageURLs"] as? [String] ?? []
        let seekerProofs: [String]
        let investorProofs: [String]
        if seekerP.isEmpty, investorP.isEmpty, !legacy.isEmpty {
            seekerProofs = legacy
            investorProofs = []
        } else {
            seekerProofs = seekerP
            investorProofs = investorP
        }
        self.init(
            installmentNo: installmentNo,
            dueDate: dueDate,
            principalComponent: principal,
            interestComponent: interest,
            totalDue: total,
            status: status,
            investorMarkedPaidAt: invPaid,
            seekerMarkedReceivedAt: seekRec,
            seekerProofImageURLs: seekerProofs,
            investorProofImageURLs: investorProofs
        )
    }

    func firestoreMap() -> [String: Any] {
        var o: [String: Any] = [
            "installmentNo": installmentNo,
            "dueDate": Timestamp(date: dueDate),
            "principalComponent": principalComponent,
            "interestComponent": interestComponent,
            "totalDue": totalDue,
            "status": status.rawValue,
            "seekerProofImageURLs": seekerProofImageURLs,
            "investorProofImageURLs": investorProofImageURLs,
            "proofImageURLs": proofImageURLs
        ]
        if let investorMarkedPaidAt {
            o["investorMarkedPaidAt"] = Timestamp(date: investorMarkedPaidAt)
        }
        if let seekerMarkedReceivedAt {
            o["seekerMarkedReceivedAt"] = Timestamp(date: seekerMarkedReceivedAt)
        }
        return o
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let v = value as? Double { return v }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}

// MARK: - Schedule generation (simple interest, equal installments)

enum LoanScheduleGenerator {
    /// Weeks per month for converting loan term (months) to weekly count.
    static let weeksPerMonth: Double = 4.345

    /// Total repayable with simple interest: principal + principal * (rate/100) * (months/12).
    static func totalRepayable(principal: Double, annualRatePercent: Double, termMonths: Int) -> Double {
        guard principal > 0, termMonths > 0 else { return max(0, principal) }
        let years = Double(termMonths) / 12.0
        let interest = principal * (annualRatePercent / 100.0) * years
        return principal + max(0, interest)
    }

    /// Builds installment rows; `startDate` is usually `acceptedAt` or agreement active date.
    static func generateSchedule(
        principal: Double,
        annualRatePercent: Double,
        termMonths: Int,
        plan: LoanRepaymentPlan,
        startDate: Date,
        calendar: Calendar = .current
    ) -> [LoanInstallment] {
        guard principal > 0, termMonths > 0 else { return [] }

        let total = totalRepayable(principal: principal, annualRatePercent: annualRatePercent, termMonths: termMonths)
        let totalInterest = max(0, total - principal)

        switch plan {
        case .one_time:
            let due = calendar.date(byAdding: .month, value: termMonths, to: startDate) ?? startDate
            return [
                LoanInstallment(
                    installmentNo: 1,
                    dueDate: due,
                    principalComponent: round2(principal),
                    interestComponent: round2(totalInterest),
                    totalDue: round2(total),
                    status: .scheduled,
                    investorMarkedPaidAt: nil,
                    seekerMarkedReceivedAt: nil,
                    seekerProofImageURLs: [],
                    investorProofImageURLs: []
                )
            ]

        case .monthly:
            let n = max(1, termMonths)
            return buildEqualInstallments(
                count: n,
                totalPrincipal: principal,
                totalInterest: totalInterest,
                calendar: calendar,
                startDate: startDate,
                addUnit: .month,
                step: 1
            )

        case .weekly:
            let weekCount = max(1, Int((Double(termMonths) * Self.weeksPerMonth).rounded()))
            return buildEqualInstallments(
                count: weekCount,
                totalPrincipal: principal,
                totalInterest: totalInterest,
                calendar: calendar,
                startDate: startDate,
                addUnit: .weekOfYear,
                step: 1
            )
        }
    }

    private static func buildEqualInstallments(
        count: Int,
        totalPrincipal: Double,
        totalInterest: Double,
        calendar: Calendar,
        startDate: Date,
        addUnit: Calendar.Component,
        step: Int
    ) -> [LoanInstallment] {
        let principalShares = equalParts(total: totalPrincipal, count: count)
        let interestShares = equalParts(total: totalInterest, count: count)
        var rows: [LoanInstallment] = []
        for i in 0..<count {
            let due = calendar.date(byAdding: addUnit, value: step * (i + 1), to: startDate) ?? startDate
            let p = principalShares[i]
            let intPart = interestShares[i]
            let totalDue = round2(p + intPart)
            rows.append(
                LoanInstallment(
                    installmentNo: i + 1,
                    dueDate: due,
                    principalComponent: round2(p),
                    interestComponent: round2(intPart),
                    totalDue: totalDue,
                    status: .scheduled,
                    investorMarkedPaidAt: nil,
                    seekerMarkedReceivedAt: nil,
                    seekerProofImageURLs: [],
                    investorProofImageURLs: []
                )
            )
        }
        return rows
    }

    /// Split `total` into `count` parts; remainder goes to last installment (2 decimal places).
    static func equalParts(total: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let raw = total / Double(count)
        var parts = (0..<count).map { _ in round2(raw) }
        let sum = parts.reduce(0, +)
        let diff = round2(total - sum)
        if count > 0, diff != 0 {
            parts[count - 1] = round2(parts[count - 1] + diff)
        }
        return parts
    }

    static func round2(_ x: Double) -> Double {
        (x * 100).rounded() / 100
    }
}
