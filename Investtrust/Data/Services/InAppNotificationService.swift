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
                notes.append(
                    InAppNotification(
                        id: "investor-principal-\(inv.id)",
                        title: needsProof ? "Upload principal proof" : "Mark principal sent",
                        message: "\(safeTitle(inv)) is waiting for principal disbursement.",
                        createdAt: inv.updatedFallbackDate,
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
        }
        return notes.sorted { $0.createdAt > $1.createdAt }
    }

    private func seekerNotifications(_ rows: [InvestmentListing], userId: String) -> [InAppNotification] {
        var notes: [InAppNotification] = []
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
        }
        return notes.sorted { $0.createdAt > $1.createdAt }
    }

    private func safeTitle(_ inv: InvestmentListing) -> String {
        let title = inv.opportunityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "your deal" : title
    }
}

private extension InvestmentListing {
    var updatedFallbackDate: Date {
        acceptedAt ?? agreementGeneratedAt ?? createdAt ?? Date.distantPast
    }
}
