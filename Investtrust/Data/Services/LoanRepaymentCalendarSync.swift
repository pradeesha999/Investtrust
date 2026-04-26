//
//  LoanRepaymentCalendarSync.swift
//  Investtrust
//

import EventKit
import Foundation

/// Adds calendar entries for loan installment due dates (all-day, one-day-before alarm) after the agreement is active.
@MainActor
enum LoanRepaymentCalendarSync {
    private static let store = EKEventStore()
    private static let persistenceKey = "investtrust.loanCalendarEventIds.v1"

    /// Replaces any previously synced events for this investment, then adds one all-day event per unpaid installment.
    static func replaceInstallmentReminders(
        investmentId: String,
        opportunityTitle: String,
        installments: [LoanInstallment],
        actingUserId: String,
        investorId: String?,
        seekerId: String?
    ) async {
        guard !investmentId.isEmpty else { return }
        guard let investorId, let seekerId else { return }
        guard actingUserId == investorId || actingUserId == seekerId else { return }
        guard !installments.isEmpty else { return }

        guard await ensureCalendarAccess() else { return }

        removeStoredEvents(forInvestmentId: investmentId)

        let calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first
        guard let defaultCal = calendar else { return }

        let titleBase = opportunityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Loan payment"
            : opportunityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalCount = installments.count
        var newIds: [String] = []

        for inst in installments where inst.status != .confirmed_paid {
            let event = EKEvent(eventStore: store)
            event.calendar = defaultCal
            event.title = "Investtrust — Pay LKR \(formatLKR(inst.totalDue)) · \(titleBase)"
            event.notes = notesForInstallment(
                opportunityTitle: titleBase,
                installment: inst,
                totalInstallments: totalCount
            )
            event.isAllDay = true
            let cal = Calendar.current
            let start = cal.startOfDay(for: inst.dueDate)
            event.startDate = start
            event.endDate = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
            event.addAlarm(EKAlarm(relativeOffset: -86400))

            do {
                try store.save(event, span: .thisEvent)
                if let id = event.eventIdentifier, !id.isEmpty {
                    newIds.append(id)
                }
            } catch {
                continue
            }
        }

        persistEventIds(newIds, investmentId: investmentId)
    }

    /// Call when the user opens the repayment hub so the other party (who did not run finalization) gets the same reminders.
    static func syncIfEligible(investment: InvestmentListing, currentUserId: String?) async {
        guard investment.investmentType == .loan else { return }
        guard investment.agreementStatus == .active else { return }
        guard !investment.loanInstallments.isEmpty else { return }
        guard let uid = currentUserId,
              uid == investment.investorId || uid == investment.seekerId
        else { return }

        await replaceInstallmentReminders(
            investmentId: investment.id,
            opportunityTitle: investment.opportunityTitle,
            installments: investment.loanInstallments,
            actingUserId: uid,
            investorId: investment.investorId,
            seekerId: investment.seekerId
        )
    }

    // MARK: - Calendar access

    private static func ensureCalendarAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .writeOnly:
            return true
        case .authorized:
            return true
        case .notDetermined:
            if #available(iOS 17.0, *) {
                do {
                    return try await store.requestWriteOnlyAccessToEvents()
                } catch {
                    return false
                }
            } else {
                return await withCheckedContinuation { cont in
                    store.requestAccess(to: .event) { granted, _ in
                        cont.resume(returning: granted)
                    }
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Persistence

    private static func removeStoredEvents(forInvestmentId investmentId: String) {
        let map = loadIdMap()
        guard let ids = map[investmentId], !ids.isEmpty else { return }
        for raw in ids {
            guard let ev = store.event(withIdentifier: raw) else { continue }
            try? store.remove(ev, span: .thisEvent)
        }
        var next = map
        next.removeValue(forKey: investmentId)
        saveIdMap(next)
    }

    private static func persistEventIds(_ ids: [String], investmentId: String) {
        var map = loadIdMap()
        map[investmentId] = ids
        saveIdMap(map)
    }

    private static func loadIdMap() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveIdMap(_ map: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    // MARK: - Copy

    private static func notesForInstallment(
        opportunityTitle: String,
        installment: LoanInstallment,
        totalInstallments: Int
    ) -> String {
        """
        Investtrust loan repayment
        Opportunity: \(opportunityTitle)
        Installment #\(installment.installmentNo) of \(totalInstallments)
        Total due: LKR \(formatLKR(installment.totalDue))
        Due date: \(mediumDate(installment.dueDate))

        Record this payment in the Investtrust app when you send or receive funds.
        """
    }

    private static func formatLKR(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.2f", v)
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }
}
