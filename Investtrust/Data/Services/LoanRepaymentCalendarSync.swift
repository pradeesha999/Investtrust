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
    private static let repaymentPersistenceKey = "investtrust.loanCalendarEventIds.v2"
    private static let milestonePersistenceKey = "investtrust.milestoneCalendarEventIds.v1"
    private static let preferenceEnabledKey = "investtrust.calendarSyncEnabled.v1"
    private static let preferenceDecidedKey = "investtrust.calendarSyncDecided.v1"
    private static let oneTimeCleanupKey = "investtrust.calendarOneTimeCleanup.v1"

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
        guard isCalendarSyncEnabled else { return }
        guard !installments.isEmpty else { return }

        guard await ensureCalendarAccess() else { return }

        removeStoredRepaymentEvents(forInvestmentId: investmentId)

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

        persistRepaymentEventIds(newIds, investmentId: investmentId)
    }

    /// Replaces milestone reminders for one investment context.
    static func replaceMilestoneReminders(
        investmentId: String,
        opportunityTitle: String,
        milestones: [OpportunityMilestone],
        acceptedAt: Date?,
        actingUserId: String,
        investorId: String?,
        seekerId: String?
    ) async {
        guard !investmentId.isEmpty else { return }
        guard let investorId, let seekerId else { return }
        guard actingUserId == investorId || actingUserId == seekerId else { return }
        guard isCalendarSyncEnabled else { return }
        guard !milestones.isEmpty else {
            removeStoredMilestoneEvents(forInvestmentId: investmentId)
            return
        }
        guard let acceptedAt else {
            removeStoredMilestoneEvents(forInvestmentId: investmentId)
            return
        }
        guard await ensureCalendarAccess() else { return }

        removeStoredMilestoneEvents(forInvestmentId: investmentId)

        let calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first
        guard let defaultCal = calendar else { return }
        let titleBase = opportunityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Milestone"
            : opportunityTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        var newIds: [String] = []
        for (idx, milestone) in milestones.enumerated() {
            guard let dueDate = resolveMilestoneDate(milestone, acceptedAt: acceptedAt) else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = defaultCal
            event.title = "Investtrust — Milestone · \(titleBase)"
            event.notes = milestoneNotes(
                title: milestone.title,
                description: milestone.description,
                dueDate: dueDate,
                index: idx + 1,
                total: milestones.count
            )
            event.isAllDay = true
            let cal = Calendar.current
            let start = cal.startOfDay(for: dueDate)
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
        persistMilestoneEventIds(newIds, investmentId: investmentId)
    }

    /// Unified sync entrypoint for post-sign events.
    static func syncPostAgreementEvents(
        investment: InvestmentListing,
        opportunity: OpportunityListing?,
        currentUserId: String?
    ) async {
        guard let uid = currentUserId,
              uid == investment.investorId || uid == investment.seekerId
        else { return }
        guard investment.agreementStatus == .active else { return }
        guard let opportunity else { return }
        guard await ensureCalendarAccess() else { return }
        performOneTimeCleanupIfNeeded()

        if investment.investmentType == .loan, !investment.loanInstallments.isEmpty {
            await replaceInstallmentReminders(
                investmentId: investment.id,
                opportunityTitle: investment.opportunityTitle,
                installments: investment.loanInstallments,
                actingUserId: uid,
                investorId: investment.investorId,
                seekerId: investment.seekerId
            )
        }
        await replaceMilestoneReminders(
            investmentId: investment.id,
            opportunityTitle: investment.opportunityTitle,
            milestones: opportunity.milestones,
            acceptedAt: investment.acceptedAt,
            actingUserId: uid,
            investorId: investment.investorId,
            seekerId: investment.seekerId
        )
    }

    /// Removes locally synced calendar rows and UserDefaults keys for this investment (e.g. after revoke or server delete).
    static func clearReminders(forInvestmentId investmentId: String) {
        removeStoredRepaymentEvents(forInvestmentId: investmentId)
        removeStoredMilestoneEvents(forInvestmentId: investmentId)
    }

    static func clearAllReminders() {
        let repaymentMap = loadRepaymentIdMap()
        for ids in repaymentMap.values {
            for raw in ids {
                guard let ev = store.event(withIdentifier: raw) else { continue }
                try? store.remove(ev, span: .thisEvent)
            }
        }
        let milestoneMap = loadMilestoneIdMap()
        for ids in milestoneMap.values {
            for raw in ids {
                guard let ev = store.event(withIdentifier: raw) else { continue }
                try? store.remove(ev, span: .thisEvent)
            }
        }
        saveRepaymentIdMap([:])
        saveMilestoneIdMap([:])
    }

    private static func performOneTimeCleanupIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: oneTimeCleanupKey) else { return }
        clearAllReminders()
        removeAllInvesttrustEventsFromCalendar()
        defaults.set(true, forKey: oneTimeCleanupKey)
    }

    static var hasCalendarSyncPreference: Bool {
        UserDefaults.standard.bool(forKey: preferenceDecidedKey)
    }

    static var isCalendarSyncEnabled: Bool {
        guard hasCalendarSyncPreference else { return false }
        return UserDefaults.standard.bool(forKey: preferenceEnabledKey)
    }

    static func setCalendarSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(true, forKey: preferenceDecidedKey)
        UserDefaults.standard.set(enabled, forKey: preferenceEnabledKey)
    }

    static func requestPermissionIfNeeded() async -> Bool {
        await ensureCalendarAccess()
    }

    /// Call when the user opens the repayment hub so the other party (who did not run finalization) gets the same reminders.
    static func syncIfEligible(investment: InvestmentListing, currentUserId: String?) async {
        guard investment.investmentType == .loan else { return }
        guard investment.agreementStatus == .active else { return }
        guard !investment.loanInstallments.isEmpty else { return }
        guard let uid = currentUserId,
              uid == investment.investorId || uid == investment.seekerId
        else { return }
        guard await ensureCalendarAccess() else { return }
        performOneTimeCleanupIfNeeded()

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

    private static func removeAllInvesttrustEventsFromCalendar() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .year, value: -10, to: Date()) ?? Date.distantPast
        let end = cal.date(byAdding: .year, value: 10, to: Date()) ?? Date.distantFuture
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let matches = store.events(matching: predicate).filter { event in
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let notes = (event.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return title.contains("investtrust") || notes.contains("investtrust")
        }
        for event in matches {
            try? store.remove(event, span: .thisEvent)
        }
        saveRepaymentIdMap([:])
        saveMilestoneIdMap([:])
    }

    // MARK: - Persistence

    private static func removeStoredRepaymentEvents(forInvestmentId investmentId: String) {
        let map = loadRepaymentIdMap()
        guard let ids = map[investmentId], !ids.isEmpty else { return }
        for raw in ids {
            guard let ev = store.event(withIdentifier: raw) else { continue }
            try? store.remove(ev, span: .thisEvent)
        }
        var next = map
        next.removeValue(forKey: investmentId)
        saveRepaymentIdMap(next)
    }

    private static func removeStoredMilestoneEvents(forInvestmentId investmentId: String) {
        let map = loadMilestoneIdMap()
        guard let ids = map[investmentId], !ids.isEmpty else { return }
        for raw in ids {
            guard let ev = store.event(withIdentifier: raw) else { continue }
            try? store.remove(ev, span: .thisEvent)
        }
        var next = map
        next.removeValue(forKey: investmentId)
        saveMilestoneIdMap(next)
    }

    private static func persistRepaymentEventIds(_ ids: [String], investmentId: String) {
        var map = loadRepaymentIdMap()
        map[investmentId] = ids
        saveRepaymentIdMap(map)
    }

    private static func persistMilestoneEventIds(_ ids: [String], investmentId: String) {
        var map = loadMilestoneIdMap()
        map[investmentId] = ids
        saveMilestoneIdMap(map)
    }

    private static func loadRepaymentIdMap() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: repaymentPersistenceKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveRepaymentIdMap(_ map: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: repaymentPersistenceKey)
    }

    private static func loadMilestoneIdMap() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: milestonePersistenceKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveMilestoneIdMap(_ map: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: milestonePersistenceKey)
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

    private static func resolveMilestoneDate(_ milestone: OpportunityMilestone, acceptedAt: Date) -> Date? {
        if let days = milestone.dueDaysAfterAcceptance, days >= 0 {
            return Calendar.current.date(byAdding: .day, value: days, to: acceptedAt)
        }
        return milestone.expectedDate
    }

    private static func milestoneNotes(
        title: String,
        description: String,
        dueDate: Date,
        index: Int,
        total: Int
    ) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Milestone" : title
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = [
            "Investtrust milestone",
            "Milestone #\(index) of \(total)",
            "Title: \(cleanTitle)",
            "Due date: \(mediumDate(dueDate))"
        ]
        if !cleanDescription.isEmpty {
            lines.append("")
            lines.append(cleanDescription)
        }
        return lines.joined(separator: "\n")
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
