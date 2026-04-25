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
    @State private var acceptingFor: InvestmentListing?
    @State private var agreementToReview: InvestmentListing?

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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if hasBlockingRequests {
                    blockingBanner
                }

                heroSection(for: opportunity)

                VStack(alignment: .leading, spacing: 10) {
                    Text(opportunity.title)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    if !opportunity.category.isEmpty {
                        Text(opportunity.category)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tagPill(text: opportunity.investmentType.displayName, icon: "chart.pie.fill", tint: auth.accentColor)
                            tagPill(text: opportunity.riskLevel.displayName + " risk", icon: "exclamationmark.shield.fill", tint: riskAccent(opportunity.riskLevel))
                            tagPill(
                                text: opportunity.verificationStatus == .verified ? "Verified" : "Unverified",
                                icon: opportunity.verificationStatus == .verified ? "checkmark.seal.fill" : "questionmark.circle.fill",
                                tint: opportunity.verificationStatus == .verified ? .green : .secondary
                            )
                            tagPill(text: opportunity.status.capitalized, icon: "circle.fill", tint: .secondary, small: true)
                        }
                    }

                    if let listed = opportunity.createdAt {
                        Text("Listed \(Self.mediumDate(listed))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                dealSnapshotCard(for: opportunity)

                if let videoRef = opportunity.effectiveVideoReference {
                    mediaCard(title: "Video walkthrough", systemImage: "play.rectangle.fill") {
                        StorageBackedVideoPlayer(
                            reference: videoRef,
                            height: 200,
                            cornerRadius: AppTheme.controlCornerRadius,
                            muted: false,
                            showsPlaybackControls: true,
                            allowFullscreenOnTap: true,
                            fullscreenPlaysMuted: false
                        )
                    }
                } else if opportunity.mediaWarnings.contains(where: { $0.localizedCaseInsensitiveContains("video") }) {
                    Text("Video didn’t upload — see notices below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !opportunity.description.isEmpty {
                    sectionCard(title: "The story", subtitle: "What investors see", systemImage: "text.quote") {
                        Text(opportunity.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                sectionCard(title: "Investment requests", subtitle: "Pending and accepted interest", systemImage: "envelope.open.fill") {
                    requestsSection
                }

                if !opportunity.mediaWarnings.isEmpty {
                    sectionCard(title: "Upload notices", subtitle: nil, systemImage: "exclamationmark.triangle.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(opportunity.mediaWarnings.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Edit listing", systemImage: "pencil")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                    .disabled(!canEditOrDelete || isDeleting)
                    .opacity(canEditOrDelete ? 1 : 0.45)
                    if !canEditOrDelete {
                        Text("Resolve pending requests to enable editing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(isDeleting ? "Deleting…" : "Delete listing", systemImage: "trash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canEditOrDelete || isDeleting)
                    .opacity(canEditOrDelete ? 1 : 0.45)
                    if !canEditOrDelete {
                        Text("Resolve pending requests to enable deletion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)

                if let actionError {
                    Text(actionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
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
        .sheet(item: $acceptingFor) { inv in
            AcceptInvestmentSheet(investment: inv, opportunity: opportunity) { message in
                guard let seekerId = auth.currentUserID else {
                    throw InvestmentService.InvestmentServiceError.notSignedIn
                }
                try await investmentService.acceptInvestmentRequest(
                    investmentId: inv.id,
                    seekerId: seekerId,
                    opportunity: opportunity,
                    verificationMessage: message
                )
                Task { @MainActor in
                    await loadInvestments()
                    onMutate()
                }
            }
        }
        .sheet(item: $agreementToReview) { inv in
            NavigationStack {
                InvestmentAgreementReviewView(
                    investment: inv,
                    canSign: inv.needsSeekerSignature(currentUserId: auth.currentUserID),
                    onSign: { signaturePNG in
                        guard let uid = auth.currentUserID else {
                            throw InvestmentService.InvestmentServiceError.notSignedIn
                        }
                        do {
                            try await investmentService.signAgreement(
                                investmentId: inv.id,
                                userId: uid,
                                signaturePNG: signaturePNG
                            )
                            await loadInvestments()
                            await MainActor.run { onMutate() }
                        } catch {
                            await loadInvestments()
                            await MainActor.run { onMutate() }
                            throw error
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var requestsSection: some View {
        if isLoadingInvestments && investments.isEmpty {
            ProgressView("Loading requests…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if let loadError {
            Text(loadError)
                .font(.footnote)
                .foregroundStyle(.red)
        } else if investments.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No requests yet")
                    .font(.subheadline.weight(.semibold))
                Text("When investors submit interest, you’ll manage them here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(investments) { inv in
                    requestRow(inv)
                }
            }
        }
    }

    private var blockingBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            Text("You have active investment requests (pending or accepted). Resolve pending offers below before you can edit or delete this listing.")
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private func heroSection(for opportunity: OpportunityListing) -> some View {
        Group {
            if opportunity.imageStoragePaths.isEmpty {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 280)
                    .overlay {
                        Image(systemName: opportunity.effectiveVideoReference != nil ? "play.rectangle.fill" : "photo")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
            } else {
                AutoPagingImageCarousel(
                    references: opportunity.imageStoragePaths,
                    height: 280,
                    cornerRadius: AppTheme.controlCornerRadius
                )
            }
        }
    }

    private func dealSnapshotCard(for o: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("At a glance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "square.grid.2x2.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                snapshotTile(
                    title: "Funding goal",
                    value: "LKR \(o.formattedAmountLKR)",
                    caption: nil,
                    icon: "target",
                    iconTint: auth.accentColor
                )
                snapshotTile(
                    title: "Min. ticket",
                    value: "LKR \(o.formattedMinimumLKR)",
                    caption: "Smallest check",
                    icon: "banknote",
                    iconTint: .secondary
                )
                snapshotTile(
                    title: "Terms (summary)",
                    value: o.termsSummaryLine,
                    caption: o.investmentType.displayName,
                    icon: "text.alignleft",
                    iconTint: .primary,
                    valueLineLimit: 3
                )
                snapshotTile(
                    title: "Key timeline",
                    value: o.repaymentLabel,
                    caption: "Schedule / horizon",
                    icon: "calendar",
                    iconTint: .secondary,
                    valueLineLimit: 2
                )
            }

            if let cap = o.maximumInvestors {
                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(auth.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Investor cap")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("At most \(cap) investors for this round.")
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func snapshotTile(
        title: String,
        value: String,
        caption: String?,
        icon: String,
        iconTint: Color,
        valueLineLimit: Int? = 2
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconTint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(valueLineLimit)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String?,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(auth.accentColor)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            content()
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func mediaCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(auth.accentColor)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func tagPill(text: String, icon: String, tint: Color, small: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(small ? .caption2 : .caption)
            Text(text)
                .font(small ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        }
        .padding(.horizontal, small ? 8 : 10)
        .padding(.vertical, small ? 5 : 7)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint)
    }

    private func riskAccent(_ r: RiskLevel) -> Color {
        switch r {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func requestRow(_ inv: InvestmentListing) -> some View {
        let pending = inv.status.lowercased() == "pending"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("LKR \(formatAmount(inv.investmentAmount))")
                    .font(.title3.weight(.bold))
                Spacer(minLength: 8)
                Text(inv.lifecycleDisplayTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor(inv).opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor(inv))
            }

            Text("\(inv.interestLabel) • \(inv.timelineLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let investorId = inv.investorId {
                NavigationLink {
                    PublicProfileView(userId: investorId)
                } label: {
                    Label("View investor profile", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(auth.accentColor)
            }

            if pending {
                HStack(spacing: 10) {
                    Button {
                        acceptingFor = inv
                    } label: {
                        Text("Accept")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)

                    Button {
                        Task { await decline(inv) }
                    } label: {
                        if decliningId == inv.id {
                            ProgressView()
                        } else {
                            Text("Decline")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(decliningId != nil)
                }
            } else if inv.agreementStatus == .pending_signatures, inv.needsSeekerSignature(currentUserId: auth.currentUserID) {
                Button {
                    agreementToReview = inv
                } label: {
                    Text("Review & sign agreement")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(auth.accentColor)
            } else if inv.agreement != nil {
                Button {
                    agreementToReview = inv
                } label: {
                    Text("View agreement")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(auth.accentColor)
            }

            if inv.isLoanWithSchedule {
                LoanInstallmentsSection(
                    investment: inv,
                    currentUserId: auth.currentUserID,
                    onRefresh: {
                        await loadInvestments()
                        await MainActor.run { onMutate() }
                    }
                )
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
        )
        .appCardShadow()
    }

    private func statusColor(_ inv: InvestmentListing) -> Color {
        switch inv.agreementStatus {
        case .active:
            return .green
        case .pending_signatures:
            return .orange
        case .none:
            break
        }
        switch inv.status.lowercased() {
        case "pending": return .orange
        case "accepted", "active": return .green
        case "declined", "rejected": return .red
        default: return .secondary
        }
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
