//
//  SeekerOpportunityDetailView.swift
//  Investtrust
//

import SwiftUI

struct SeekerOpportunityDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var opportunity: OpportunityListing
    @State private var investments: [InvestmentListing] = []
    @State private var isLoadingInvestments = false
    @State private var loadError: String?

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var actionError: String?
    @State private var decliningId: String?

    private let investmentService = InvestmentService()
    private let opportunityService = OpportunityService()

    var onMutate: () -> Void

    init(opportunity: OpportunityListing, onMutate: @escaping () -> Void = {}) {
        _opportunity = State(initialValue: opportunity)
        self.onMutate = onMutate
    }

    private var hasBlockingRequests: Bool {
        investments.contains { $0.blocksSeekerFromManagingOpportunity }
    }

    private var canEditOrDelete: Bool {
        !hasBlockingRequests
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if hasBlockingRequests {
                    blockingBanner
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(opportunity.title)
                        .font(.title2.bold())
                    Text(opportunity.category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("LKR \(opportunity.formattedAmountLKR)")
                        Text("•")
                        Text("\(opportunity.interestRate)%")
                        Text("•")
                        Text(opportunity.repaymentLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(opportunity.description)
                    .font(.body)

                Divider()

                Text("Investment requests")
                    .font(.headline)

                if isLoadingInvestments && investments.isEmpty {
                    ProgressView("Loading requests…")
                        .frame(maxWidth: .infinity)
                } else if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if investments.isEmpty {
                    Text("No requests yet. You can edit or delete this listing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(investments) { inv in
                        requestRow(inv)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Edit listing", systemImage: "pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                    .disabled(!canEditOrDelete || isDeleting)
                    .opacity(canEditOrDelete ? 1 : 0.45)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(isDeleting ? "Deleting…" : "Delete listing", systemImage: "trash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canEditOrDelete || isDeleting)
                    .opacity(canEditOrDelete ? 1 : 0.45)
                }
                .padding(.top, 8)

                if let actionError {
                    Text(actionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your listing")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: opportunity.id) {
            await syncVideoDownloadURLIfOwner()
            await loadInvestments()
        }
        .refreshable { await loadInvestments() }
        .sheet(isPresented: $showEdit) {
            EditOpportunityView(opportunity: opportunity) { draft in
                guard let uid = auth.currentUserID else {
                    throw NSError(
                        domain: "Investtrust",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Please sign in again."]
                    )
                }
                let updated = try await opportunityService.updateOpportunity(
                    opportunityId: opportunity.id,
                    ownerId: uid,
                    draft: draft
                )
                opportunity = updated
                onMutate()
            }
        }
        .alert("Delete this listing?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteListing() }
            }
        } message: {
            Text("This removes the opportunity from the market. Related declined requests are cleared from your dashboard data.")
        }
    }

    private var blockingBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            Text("You have pending investment requests. Decline each offer below before you can edit or delete this listing.")
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func requestRow(_ inv: InvestmentListing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LKR \(formatAmount(inv.investmentAmount))")
                        .font(.subheadline.weight(.semibold))
                    Text("Status: \(inv.status.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let investor = inv.investorId {
                        Text("Investor: \(shortId(investor))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if inv.blocksSeekerFromManagingOpportunity {
                    Button {
                        Task { await decline(inv) }
                    } label: {
                        if decliningId == inv.id {
                            ProgressView()
                        } else {
                            Text("Decline")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(decliningId != nil)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shortId(_ id: String) -> String {
        guard id.count > 10 else { return id }
        return "\(id.prefix(6))…\(id.suffix(4))"
    }

    private func formatAmount(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }

    private func syncVideoDownloadURLIfOwner() async {
        guard let uid = auth.currentUserID, uid == opportunity.ownerId else { return }
        let hasHTTPS = !(opportunity.videoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if hasHTTPS { return }
        guard let path = opportunity.videoStoragePath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            if let updated = try await opportunityService.syncVideoDownloadURLIfNeeded(opportunityId: opportunity.id, ownerId: uid) {
                opportunity = updated
                onMutate()
            }
        } catch {
            // Path-based playback may still work for the owner; investors need videoURL or permissive rules.
        }
    }

    private func loadInvestments() async {
        loadError = nil
        isLoadingInvestments = true
        defer { isLoadingInvestments = false }
        do {
            investments = try await investmentService.fetchInvestmentsForOpportunity(opportunityId: opportunity.id)
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func decline(_ inv: InvestmentListing) async {
        guard let seekerId = auth.currentUserID else { return }
        actionError = nil
        decliningId = inv.id
        defer { decliningId = nil }
        do {
            try await investmentService.declineInvestmentRequest(investmentId: inv.id, seekerId: seekerId)
            await loadInvestments()
            onMutate()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func deleteListing() async {
        guard let uid = auth.currentUserID else { return }
        actionError = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await opportunityService.deleteOpportunity(opportunityId: opportunity.id, ownerId: uid)
            onMutate()
            dismiss()
        } catch {
            if let le = error as? LocalizedError, let d = le.errorDescription {
                actionError = d
            } else {
                actionError = (error as NSError).localizedDescription
            }
        }
    }
}
