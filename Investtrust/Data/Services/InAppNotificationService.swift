import Foundation

final class InAppNotificationService {
    private let investmentService = InvestmentService()

    func fetchNotifications(
        userId: String,
        activeProfile: UserProfile.ActiveProfile
    ) async throws -> [InAppNotification] {
        switch activeProfile {
        case .investor:
            let rows = try await investmentService.fetchInvestments(forInvestor: userId, limit: 120)
            return investorNotifications(rows, userId: userId)
        case .seeker:
            let rows = try await investmentService.fetchInvestmentsForSeeker(seekerId: userId, limit: 200)
            return seekerNotifications(rows, userId: userId)
        }
    }

    private func investorNotifications(_ rows: [InvestmentListing], userId: String) -> [InAppNotification] {
        var notes: [InAppNotification] = []
        if !LoanRepaymentCalendarSync.hasCalendarSyncPreference,
           rows.contains(where: { $0.agreementStatus == .active }) {
            notes.append(
                InAppNotification(
                    id: "calendar-consent-investor-\(userId)",
                    title: "Enable calendar reminders",
                    message: "Turn on calendar sync to add repayment and milestone reminders.",
                    createdAt: Date(),
                    kind: .actionRequired,
                    route: .dashboard
                )
            )
        }
        for inv in rows {
            if inv.agreementStatus == .pending_signatures, inv.needsInvestorSignature(currentUserId: userId) {
                notes.append(
                    InAppNotification(
                        id: "investor-sign-\(inv.id)",
                        title: "Signature required",
                        message: "Sign the agreement for \(safeTitle(inv)).",
                        createdAt: inv.updatedFallbackDate,
                        kind: .actionRequired,
                        route: .actionMyRequests
                    )
                )
            }
            if inv.investmentType == .loan, inv.fundingStatus == .awaiting_disbursement, inv.principalSentByInvestorAt == nil {
                let needsProof = inv.principalInvestorProofImageURLs.isEmpty
                let seekerReported = inv.principalSeekerNotReceivedReason != nil
                notes.append(
                    InAppNotification(
                        id: seekerReported ? "investor-principal-retry-\(inv.id)" : "investor-principal-\(inv.id)",
                        title: seekerReported ? "Seeker reported principal not received" : (needsProof ? "Upload principal proof" : "Mark principal sent"),
                        message: seekerReported
                            ? "\(safeTitle(inv)): upload new transfer proof and mark sent again."
                            : "\(safeTitle(inv)) is waiting for principal disbursement.",
                        createdAt: inv.principalSeekerNotReceivedAt ?? inv.updatedFallbackDate,
                        kind: .actionRequired,
                        route: .actionOngoing
                    )
                )
            }
            if inv.investmentType == .loan,
               inv.fundingStatus == .disbursed,
               let next = inv.nextOpenLoanInstallment,
               next.seekerMarkedReceivedAt != nil,
               next.investorMarkedPaidAt == nil {
                notes.append(
                    InAppNotification(
                        id: "investor-installment-\(inv.id)-\(next.installmentNo)",
                        title: "Payment confirmation needed",
                        message: "Review and confirm installment #\(next.installmentNo) for \(safeTitle(inv)).",
                        createdAt: next.seekerMarkedReceivedAt ?? inv.updatedFallbackDate,
                        kind: .actionRequired,
                        route: .actionOngoing
                    )
                )
            }
            if inv.investmentType == .equity,
               inv.agreementStatus == .active,
               let latest = inv.equityUpdates.first {
                notes.append(
                    InAppNotification(
                        id: "investor-equity-update-\(inv.id)-\(latest.id)",
                        title: "New venture update",
                        message: "\(safeTitle(inv)): \(latest.title)",
                        createdAt: latest.createdAt,
                        kind: .actionRequired,
                        route: .actionOngoing
                    )
                )
            }
        }
        return notes.sorted { $0.createdAt > $1.createdAt }
    }

    private func seekerNotifications(_ rows: [InvestmentListing], userId: String) -> [InAppNotification] {
        var notes: [InAppNotification] = []
        if !LoanRepaymentCalendarSync.hasCalendarSyncPreference,
           rows.contains(where: { $0.agreementStatus == .active }) {
            notes.append(
                InAppNotification(
                    id: "calendar-consent-seeker-\(userId)",
                    title: "Enable calendar reminders",
                    message: "Turn on calendar sync to add repayment and milestone reminders.",
                    createdAt: Date(),
                    kind: .actionRequired,
                    route: .dashboard
                )
            )
        }
        for inv in rows {
            let status = inv.status.lowercased()
            if status == "pending" {
                notes.append(
                    InAppNotification(
                        id: "seeker-pending-\(inv.id)",
                        title: "Review investment request",
                        message: "A new request is waiting on \(safeTitle(inv)).",
                        createdAt: inv.updatedFallbackDate,
                        kind: .actionRequired,
                        route: .actionSeekerOpportunity
                    )
                )
            }
            if inv.agreementStatus == .pending_signatures, inv.needsSeekerSignature(currentUserId: userId) {
                notes.append(
                    InAppNotification(
                        id: "seeker-sign-\(inv.id)",
                        title: "Signature required",
                        message: "Sign the agreement for \(safeTitle(inv)).",
                        createdAt: inv.updatedFallbackDate,
                        kind: .actionRequired,
                        route: .actionSeekerOpportunity
                    )
                )
            }
            if inv.investmentType == .loan,
               inv.fundingStatus == .awaiting_disbursement,
               inv.principalSentByInvestorAt != nil,
               inv.principalReceivedBySeekerAt == nil {
                notes.append(
                    InAppNotification(
                        id: "seeker-principal-\(inv.id)",
                        title: "Confirm principal received",
                        message: "Principal has been marked sent for \(safeTitle(inv)).",
                        createdAt: inv.principalSentByInvestorAt ?? inv.updatedFallbackDate,
                        kind: .actionRequired,
                        route: .actionSeekerOpportunity
                    )
                )
            }
            if inv.investmentType == .loan,
               inv.fundingStatus == .disbursed,
               let next = inv.nextOpenLoanInstallment {
                if next.status == .disputed, next.seekerMarkedReceivedAt == nil {
                    notes.append(
                        InAppNotification(
                            id: "seeker-disputed-\(inv.id)-\(next.installmentNo)",
                            title: "Payment proof requested again",
                            message: "Investor marked installment #\(next.installmentNo) as not received for \(safeTitle(inv)).",
                            createdAt: next.latestDisputedAt ?? inv.updatedFallbackDate,
                            kind: .actionRequired,
                            route: .actionSeekerOpportunity
                        )
                    )
                } else if next.status == .scheduled, next.seekerMarkedReceivedAt == nil {
                    notes.append(
                        InAppNotification(
                            id: "seeker-upcoming-\(inv.id)-\(next.installmentNo)",
                            title: "Upcoming repayment",
                            message: "Submit proof for installment #\(next.installmentNo) on \(safeTitle(inv)).",
                            createdAt: next.dueDate,
                            kind: .info,
                            route: .actionSeekerOpportunity
                        )
                    )
                }
            }
            if inv.investmentType == .loan,
               let accepted = latestAcceptedInstallment(in: inv) {
                notes.append(
                    InAppNotification(
                        id: "seeker-payment-accepted-\(inv.id)-\(accepted.installmentNo)",
                        title: "Payment accepted",
                        message: "Investor confirmed installment #\(accepted.installmentNo) for \(safeTitle(inv)).",
                        createdAt: accepted.investorMarkedPaidAt ?? inv.updatedFallbackDate,
                        kind: .info,
                        route: .actionSeekerOpportunity
                    )
                )
            }
            if inv.investmentType == .equity,
               inv.agreementStatus == .active,
               inv.equityUpdates.isEmpty {
                notes.append(
                    InAppNotification(
                        id: "seeker-equity-post-\(inv.id)",
                        title: "Post your first venture update",
                        message: "Share progress with investors for \(safeTitle(inv)).",
                        createdAt: inv.updatedFallbackDate,
                        kind: .actionRequired,
                        route: .actionSeekerOpportunity
                    )
                )
            }
        }
        return notes.sorted { $0.createdAt > $1.createdAt }
    }

    private func safeTitle(_ inv: InvestmentListing) -> String {
        let title = inv.opportunityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "your deal" : title
    }

    private func latestAcceptedInstallment(in inv: InvestmentListing) -> LoanInstallment? {
        inv.loanInstallments
            .filter { $0.status == .confirmed_paid && $0.investorMarkedPaidAt != nil }
            .max { ($0.investorMarkedPaidAt ?? .distantPast) < ($1.investorMarkedPaidAt ?? .distantPast) }
    }
}

private extension InvestmentListing {
    var updatedFallbackDate: Date {
        acceptedAt ?? agreementGeneratedAt ?? createdAt ?? Date.distantPast
    }
}
