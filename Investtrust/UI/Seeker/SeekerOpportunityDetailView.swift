//
//  SeekerOpportunityDetailView.swift
//  Investtrust
//

import PhotosUI
import SwiftUI
import VisionKit

struct SeekerOpportunityDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var opportunity: OpportunityListing
    @State private var investments: [InvestmentListing] = []
    @State private var isLoadingInvestments = false
    @State private var loadError: String?

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var actionError: String?
    @State private var actionSuccess: String?
    @State private var decliningId: String?
    @State private var acceptingFor: InvestmentListing?
    @State private var agreementToReview: InvestmentListing?
    @State private var showReviewRequestsSheet = false
    @State private var investorProfilesById: [String: UserProfile] = [:]
    @State private var principalConfirmBusyId: String?
    @State private var principalProofBusyId: String?
    @State private var showPrincipalProofLibrary = false
    @State private var showPrincipalProofCamera = false
    @State private var principalProofPreviewItem: PrincipalProofPreviewItem?
    @State private var showCalendarSyncPrompt = false
    @State private var principalProofLibraryItem: PhotosPickerItem?
    @State private var principalProofTargetInvestmentId: String?
    @State private var equityUpdateTitle = ""
    @State private var equityUpdateMessage = ""
    @State private var equityGrowthMetric = ""
    @State private var equityStage: VentureStage = .idea_stage
    @State private var equityUpdateBusy = false

    private let investmentService = InvestmentService()
    private let opportunityService = OpportunityService()
    private let userService = UserService()
    private let chatService = ChatService()

    private struct PrincipalProofPreviewItem: Identifiable {
        let url: String
        var id: String { url }
    }

    var onMutate: () -> Void
    var onAcceptedRequest: (() -> Void)?

    init(
        opportunity: OpportunityListing,
        autoOpenRequestsSheet: Bool = false,
        onMutate: @escaping () -> Void = {},
        onAcceptedRequest: (() -> Void)? = nil
    ) {
        _ = autoOpenRequestsSheet
        _opportunity = State(initialValue: opportunity)
        self.onMutate = onMutate
        self.onAcceptedRequest = onAcceptedRequest
    }

    private var hasBlockingRequests: Bool {
        investments.contains { $0.blocksSeekerFromManagingOpportunity }
    }

    private var canEditOrDelete: Bool {
        !hasBlockingRequests
    }

    private var hasAcceptedOrActiveDeal: Bool {
        investments.contains { inv in
            let s = inv.status.lowercased()
            return s == "accepted" || s == "active" || s == "completed" || inv.agreementStatus != .none
        }
    }

    private var shouldHideRequestsAfterAcceptance: Bool {
        hasAcceptedOrActiveDeal
    }

    private var pendingRequestRows: [InvestmentListing] {
        let pending = investments.filter { $0.status.lowercased() == "pending" }
        var bestByInvestor: [String: InvestmentListing] = [:]
        var anonymous: [InvestmentListing] = []
        for row in pending {
            guard let investorId = row.investorId, !investorId.isEmpty else {
                anonymous.append(row)
                continue
            }
            if let existing = bestByInvestor[investorId] {
                let preferred: InvestmentListing
                if row.isOfferRequest != existing.isOfferRequest {
                    preferred = row.isOfferRequest ? row : existing
                } else {
                    preferred = row.recencyDate > existing.recencyDate ? row : existing
                }
                bestByInvestor[investorId] = preferred
            } else {
                bestByInvestor[investorId] = row
            }
        }
        let merged = Array(bestByInvestor.values) + anonymous
        return merged.sorted { $0.recencyDate > $1.recencyDate }
    }

    private var primarySingleInvestorDeal: InvestmentListing? {
        if let pendingSign = investments.first(where: { $0.agreementStatus == .pending_signatures }) {
            return pendingSign
        }
        if let active = investments.first(where: { $0.agreementStatus == .active || $0.status.lowercased() == "active" }) {
            return active
        }
        if let completed = investments.first(where: { $0.status.lowercased() == "completed" }) {
            return completed
        }
        return investments.first(where: { $0.status.lowercased() == "accepted" })
    }

    /// Loan deals on this listing with a fully active agreement (repayment / funding UI).
    private var activeLoanDealsForDashboard: [InvestmentListing] {
        investments.filter { inv in
            guard inv.investmentType == .loan else { return false }
            let oid = inv.opportunityId ?? ""
            guard oid.isEmpty || oid == opportunity.id else { return false }
            let s = inv.status.lowercased()
            return inv.agreementStatus == .active || s == "active"
        }
    }

    private var showSeekerLoanRepaymentDashboard: Bool {
        opportunity.investmentType == .loan && !activeLoanDealsForDashboard.isEmpty
    }

    private var activeEquityDealsForDashboard: [InvestmentListing] {
        investments.filter { inv in
            guard inv.investmentType == .equity else { return false }
            let s = inv.status.lowercased()
            return inv.agreementStatus == .active || s == "active"
        }
    }

    private var seekerLoanScheduleAggregate: (next: (investment: InvestmentListing, installment: LoanInstallment)?, paidCount: Int, totalCount: Int, remainingTotal: Double, paidTotal: Double) {
        var paidCount = 0
        var totalCount = 0
        var remainingTotal = 0.0
        var paidTotal = 0.0
        var best: (InvestmentListing, LoanInstallment)?
        var bestDue: Date?

        for inv in activeLoanDealsForDashboard {
            let sorted = inv.loanInstallments.sorted { $0.installmentNo < $1.installmentNo }
            for row in sorted {
                totalCount += 1
                if row.status == .confirmed_paid {
                    paidCount += 1
                    paidTotal += row.totalDue
                } else {
                    remainingTotal += row.totalDue
                    if bestDue == nil || row.dueDate < bestDue! {
                        bestDue = row.dueDate
                        best = (inv, row)
                    }
                }
            }
        }
        return (best, paidCount, totalCount, remainingTotal, paidTotal)
    }

    @ViewBuilder
    private var seekerLoanRepaymentDashboardStack: some View {
        if activeLoanDealsForDashboard.contains(where: {
            $0.fundingStatus == .awaiting_disbursement
                && $0.principalReceivedBySeekerAt == nil
        }) {
            seekerPrincipalFundingCard
                .padding(.horizontal, AppTheme.screenPadding)
        }

        if let deal = primarySingleInvestorDeal ?? activeLoanDealsForDashboard.first, deal.agreement != nil {
            Button {
                agreementToReview = deal
            } label: {
                Label(
                    deal.agreementStatus == .pending_signatures && deal.needsSeekerSignature(currentUserId: auth.currentUserID)
                        ? "Review & sign agreement"
                        : "View agreement & MOA",
                    systemImage: "doc.text.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(auth.accentColor)
            .padding(.horizontal, AppTheme.screenPadding)
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("Repayment schedules")
                .font(.headline)
                .padding(.horizontal, AppTheme.screenPadding)
            Text("Open a schedule to review and record payments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.screenPadding)

            ForEach(activeLoanDealsForDashboard.sorted(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })) { inv in
                VStack(alignment: .leading, spacing: 8) {
                    if activeLoanDealsForDashboard.count > 1 {
                        let name = displayName(for: inv.investorId.flatMap { investorProfilesById[$0] }, investorId: inv.investorId)
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, AppTheme.screenPadding)
                    }
                    LoanInstallmentsSection(
                        investment: inv,
                        currentUserId: auth.currentUserID,
                        onRefresh: {
                            await loadInvestments()
                            await MainActor.run { onMutate() }
                        }
                    )
                    .padding(.horizontal, AppTheme.screenPadding)
                }
            }
        }

        VStack(alignment: .leading, spacing: 16) {
            overviewCard(for: opportunity)
            keyNumbersCard(for: opportunity)
            incomeFundsTimelineCard(for: opportunity)
            dealTermsCard(for: opportunity)
            executionPlanCard(for: opportunity)
        }
        .padding(.horizontal, AppTheme.screenPadding)
    }

    private func seekerRepaymentCommandCenter(
        aggregate: (next: (investment: InvestmentListing, installment: LoanInstallment)?, paidCount: Int, totalCount: Int, remainingTotal: Double, paidTotal: Double),
        onRefresh: @escaping () async -> Void
    ) -> some View {
        let anyUnconfirmedFunding = activeLoanDealsForDashboard.contains {
            $0.fundingStatus == .awaiting_disbursement && $0.principalReceivedBySeekerAt == nil
        }
        let repaymentsLive = activeLoanDealsForDashboard.allSatisfy(\.loanRepaymentsUnlocked)

        return sectionCard(
            title: "Loan repayments",
            subtitle: repaymentsLive ? "Track installments and due dates." : "Locked until principal confirmation.",
            systemImage: "banknote.fill"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if anyUnconfirmedFunding, !repaymentsLive {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                        Text("Waiting for principal confirmation")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                } else if aggregate.totalCount == 0 {
                    Text("Installment schedule will appear here once the agreement is fully active.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let pair = aggregate.next {
                    let days = Self.calendarDaysFromToday(to: pair.installment.dueDate)
                    let overdue = days < 0 && pair.installment.status != .confirmed_paid

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next payment")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("LKR \(formatAmount(pair.installment.totalDue))")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)

                        Text(Self.nextPaymentTimingLabel(days: days))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(overdue ? .red : auth.accentColor)

                        Text("Due \(Self.mediumDate(pair.installment.dueDate)) · #\(pair.installment.installmentNo)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if activeLoanDealsForDashboard.count > 1,
                           let iid = pair.investment.investorId {
                            Text("Investor: \(displayName(for: investorProfilesById[iid], investorId: iid))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if aggregate.totalCount > 0 {
                        ProgressView(value: Double(aggregate.paidCount), total: Double(aggregate.totalCount))
                            .tint(auth.accentColor)
                        Text("\(aggregate.paidCount) of \(aggregate.totalCount) installments paid")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        seekerMetricPill(title: "Left to pay", value: "LKR \(formatAmount(aggregate.remainingTotal))", tint: .primary)
                        seekerMetricPill(title: "Paid (confirmed)", value: "LKR \(formatAmount(aggregate.paidTotal))", tint: .green)
                    }
                    .padding(.top, 10)
                    

                    if pair.investment.loanRepaymentsUnlocked,
                       auth.currentUserID == pair.investment.seekerId,
                       pair.installment.status != .confirmed_paid {
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Record this payment")
                                .font(.headline)
                            Text("Upload your bank slip or receipt, then confirm when the money has reached you.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            SeekerLoanPaymentConfirmBlock(
                                investment: pair.investment,
                                installmentNo: pair.installment.installmentNo,
                                onRefresh: onRefresh
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("All installments are marked paid.")
                            .font(.headline)
                        Text("Total confirmed: LKR \(formatAmount(aggregate.paidTotal))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            }
        }
    }

    private func seekerMetricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    private var seekerPrincipalFundingCard: some View {
        sectionCard(
            title: "Principal & funding",
            subtitle: "Confirm transfer before repayments unlock.",
            systemImage: "banknote.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(activeLoanDealsForDashboard.filter {
                    $0.fundingStatus == .awaiting_disbursement && $0.principalReceivedBySeekerAt == nil
                }) { inv in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(displayName(for: inv.investorId.flatMap { investorProfilesById[$0] }, investorId: inv.investorId))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("LKR \(formatAmount(inv.effectiveAmount))")
                                .font(.subheadline.weight(.bold))
                        }
                        if inv.principalSentByInvestorAt == nil {
                            Label("Waiting for investor transfer", systemImage: "clock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.14), in: Capsule())
                        } else {
                            Label("Action required", systemImage: "exclamationmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(auth.accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(auth.accentColor.opacity(0.14), in: Capsule())
                            if !inv.principalInvestorProofImageURLs.isEmpty {
                                principalProofStrip(
                                    title: "Investor transfer proof",
                                    urls: inv.principalInvestorProofImageURLs,
                                    tint: .orange
                                )
                            }
                            if !inv.principalSeekerProofImageURLs.isEmpty {
                                principalProofStrip(
                                    title: "Your receiving proof",
                                    urls: inv.principalSeekerProofImageURLs,
                                    tint: .green
                                )
                            }
                            if inv.principalSeekerProofImageURLs.isEmpty {
                                Menu {
                                    if VNDocumentCameraViewController.isSupported {
                                        Button {
                                            principalProofTargetInvestmentId = inv.id
                                            showPrincipalProofCamera = true
                                        } label: {
                                            Label("Scan proof", systemImage: "doc.viewfinder")
                                        }
                                    }
                                    Button {
                                        principalProofTargetInvestmentId = inv.id
                                        showPrincipalProofLibrary = true
                                    } label: {
                                        Label("Upload from photos", systemImage: "photo")
                                    }
                                } label: {
                                    Label(
                                        principalProofBusyId == inv.id ? "Uploading..." : "Attach receiving proof",
                                        systemImage: "paperclip"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.bordered)
                                .disabled(principalProofBusyId != nil)
                            }
                            if inv.principalSentByInvestorAt != nil {
                                Button {
                                    Task { await confirmPrincipalReceived(investmentId: inv.id) }
                                } label: {
                                    Group {
                                        if principalConfirmBusyId == inv.id {
                                            ProgressView()
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                        } else {
                                            Text("Confirm principal received")
                                                .font(.subheadline.weight(.semibold))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(auth.accentColor)
                                .disabled(principalConfirmBusyId != nil || inv.principalSeekerProofImageURLs.isEmpty)
                            }
                        }
                    }
                    .padding(12)
                    .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }
            }
        }
        .sheet(isPresented: $showPrincipalProofLibrary) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Choose proof of receiving the principal transfer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    PhotosPicker(selection: $principalProofLibraryItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle.angled")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                }
                .padding(AppTheme.screenPadding)
                .navigationTitle("Principal proof")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            principalProofLibraryItem = nil
                            principalProofTargetInvestmentId = nil
                            showPrincipalProofLibrary = false
                        }
                    }
                }
                .onChange(of: principalProofLibraryItem) { _, item in
                    guard let item, let id = principalProofTargetInvestmentId else { return }
                    showPrincipalProofLibrary = false
                    principalProofTargetInvestmentId = nil
                    Task {
                        await uploadPrincipalProofFromPicker(item: item, investmentId: id)
                        await MainActor.run { principalProofLibraryItem = nil }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showPrincipalProofCamera) {
            Group {
                if VNDocumentCameraViewController.isSupported {
                    DocumentCameraView { images in
                        showPrincipalProofCamera = false
                        guard let id = principalProofTargetInvestmentId else { return }
                        principalProofTargetInvestmentId = nil
                        Task { await uploadPrincipalProofScans(images, investmentId: id) }
                    }
                } else {
                    NavigationStack {
                        ContentUnavailableView(
                            "Scanner unavailable",
                            systemImage: "doc.viewfinder",
                            description: Text("Use upload from photos instead.")
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    showPrincipalProofCamera = false
                                    principalProofTargetInvestmentId = nil
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $principalProofPreviewItem) { item in
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    StorageBackedAsyncImage(
                        reference: item.url,
                        height: min(UIScreen.main.bounds.height * 0.72, 560),
                        cornerRadius: 16,
                        feedThumbnail: false
                    )
                    .padding(.horizontal, AppTheme.screenPadding)
                }
                .navigationTitle("Proof image")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func confirmPrincipalReceived(investmentId: String) async {
        guard let uid = auth.currentUserID else { return }
        actionError = nil
        principalConfirmBusyId = investmentId
        defer { principalConfirmBusyId = nil }
        do {
            try await investmentService.confirmPrincipalReceivedBySeeker(investmentId: investmentId, userId: uid)
            await loadInvestments()
            await MainActor.run { onMutate() }
        } catch {
            if let le = error as? LocalizedError, let d = le.errorDescription {
                actionError = d
            } else {
                actionError = (error as NSError).localizedDescription
            }
        }
    }

    private func uploadPrincipalProofFromPicker(item: PhotosPickerItem, investmentId: String) async {
        guard let uid = auth.currentUserID else { return }
        principalProofBusyId = investmentId
        defer { principalProofBusyId = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self), !raw.isEmpty else {
            actionError = "Couldn’t read that image."
            return
        }
        let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: raw)
        guard !jpeg.isEmpty else {
            actionError = "Couldn’t convert that image."
            return
        }
        do {
            try await investmentService.attachPrincipalDisbursementProof(
                investmentId: investmentId,
                userId: uid,
                imageJPEG: jpeg
            )
            await loadInvestments()
            await MainActor.run { onMutate() }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func uploadPrincipalProofScans(_ scans: [Data], investmentId: String) async {
        guard let uid = auth.currentUserID else { return }
        principalProofBusyId = investmentId
        defer { principalProofBusyId = nil }
        for scan in scans {
            let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: scan)
            guard !jpeg.isEmpty else { continue }
            do {
                try await investmentService.attachPrincipalDisbursementProof(
                    investmentId: investmentId,
                    userId: uid,
                    imageJPEG: jpeg
                )
            } catch {
                actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
            }
        }
        await loadInvestments()
        await MainActor.run { onMutate() }
    }

    private func principalProofStrip(title: String, urls: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(urls, id: \.self) { url in
                        Button {
                            principalProofPreviewItem = PrincipalProofPreviewItem(url: url)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                StorageBackedAsyncImage(reference: url, height: 104, cornerRadius: 12, feedThumbnail: true)
                                    .frame(width: 104, height: 104)
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.6), in: Circle())
                                    .padding(6)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private static func calendarDaysFromToday(to due: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDue = cal.startOfDay(for: due)
        return cal.dateComponents([.day], from: today, to: startDue).day ?? 0
    }

    private static func nextPaymentTimingLabel(days: Int) -> String {
        if days < 0 {
            let n = -days
            return n == 1 ? "1 day overdue" : "\(n) days overdue"
        }
        if days == 0 { return "Due today" }
        if days == 1 { return "In 1 day" }
        return "In \(days) days"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if hasBlockingRequests {
                    blockingBanner
                        .padding(.horizontal, AppTheme.screenPadding)
                }

                heroSection(for: opportunity)
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.top, 8)

                if showSeekerLoanRepaymentDashboard {
                    seekerLoanRepaymentDashboardStack
                } else {
                    if !activeEquityDealsForDashboard.isEmpty {
                        seekerEquityProgressSection
                            .padding(.horizontal, AppTheme.screenPadding)
                    }
                    overviewCard(for: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                    keyNumbersCard(for: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                    incomeFundsTimelineCard(for: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                    dealTermsCard(for: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                    executionPlanCard(for: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                }

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
                    .padding(.horizontal, AppTheme.screenPadding)
                } else if opportunity.mediaWarnings.contains(where: { $0.localizedCaseInsensitiveContains("video") }) {
                    Text("Video didn’t upload — see notices below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppTheme.screenPadding)
                }

                if !showSeekerLoanRepaymentDashboard {
                    if shouldHideRequestsAfterAcceptance {
                        singleInvestorDealCard
                            .padding(.horizontal, AppTheme.screenPadding)
                    }
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
                    .padding(.horizontal, AppTheme.screenPadding)
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
                .padding(.horizontal, AppTheme.screenPadding)

                if let actionError {
                    Text(actionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, AppTheme.screenPadding)
                }
                if let actionSuccess {
                    Text(actionSuccess)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, AppTheme.screenPadding)
                }
            }
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your listing")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: opportunity.id) {
            await syncVideoDownloadURLIfOwner()
            await loadInvestments()
        }
        .refreshable { await loadInvestments() }
        .safeAreaInset(edge: .bottom) {
            if !pendingRequestRows.isEmpty {
                HStack {
                    Button {
                        showReviewRequestsSheet = true
                    } label: {
                        Label(
                            pendingRequestRows.count == 1 ? "Review 1 request" : "Review \(pendingRequestRows.count) requests",
                            systemImage: "person.2.badge.gearshape.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
            }
        }
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
                    showReviewRequestsSheet = false
                    acceptingFor = nil
                    actionError = nil
                    actionSuccess = "Request accepted and investor notified."
                    await loadInvestments()
                    onMutate()
                    onAcceptedRequest?()
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
                    },
                    onDidFinishSigning: {}
                )
            }
        }
        .sheet(isPresented: $showReviewRequestsSheet) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        if pendingRequestRows.isEmpty {
                            Text("No pending requests right now.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        } else {
                            ForEach(pendingRequestRows) { inv in
                                requestRow(inv)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Investor requests")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showReviewRequestsSheet = false }
                    }
                }
            }
        }
        .alert("Sync due dates to Calendar?", isPresented: $showCalendarSyncPrompt) {
            Button("Not now", role: .cancel) {
                LoanRepaymentCalendarSync.setCalendarSyncEnabled(false)
            }
            Button("Enable") {
                Task {
                    LoanRepaymentCalendarSync.setCalendarSyncEnabled(true)
                    let granted = await LoanRepaymentCalendarSync.requestPermissionIfNeeded()
                    if !granted {
                        LoanRepaymentCalendarSync.setCalendarSyncEnabled(false)
                        return
                    }
                    if let uid = auth.currentUserID {
                        for row in investments where row.agreementStatus == .active {
                            await LoanRepaymentCalendarSync.syncPostAgreementEvents(
                                investment: row,
                                opportunity: opportunity,
                                currentUserId: uid
                            )
                        }
                    }
                }
            }
        } message: {
            Text("Investtrust can add repayment and milestone reminders for active deals.")
        }
    }

    private var seekerEquityProgressSection: some View {
        sectionCard(
            title: "Equity progress updates",
            subtitle: "Post venture updates and move milestones as your venture grows.",
            systemImage: "chart.line.uptrend.xyaxis"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                fieldLike("Update title", text: $equityUpdateTitle, placeholder: "Prototype completed")
                fieldLike("Growth metric (optional)", text: $equityGrowthMetric, placeholder: "1,000 users")
                fieldLike("Update message", text: $equityUpdateMessage, placeholder: "Share what changed and what comes next", multiline: true)
                Picker("Venture stage", selection: $equityStage) {
                    ForEach(VentureStage.allCases, id: \.self) { stage in
                        Text(stage.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(stage)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    Task { await postEquityUpdate() }
                } label: {
                    Text(equityUpdateBusy ? "Posting..." : "Post update")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(auth.accentColor)
                .disabled(equityUpdateBusy || equityUpdateMessage.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)

                ForEach(activeEquityDealsForDashboard) { inv in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(inv.opportunityTitle.isEmpty ? "Equity deal" : inv.opportunityTitle)
                            .font(.subheadline.weight(.semibold))
                        ForEach(inv.equityMilestones) { milestone in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(milestone.title)
                                        .font(.footnote.weight(.semibold))
                                    Text(milestone.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu("Update status") {
                                    Button("Planned") { Task { await setMilestoneStatus(inv.id, milestone.title, .planned) } }
                                    Button("In Progress") { Task { await setMilestoneStatus(inv.id, milestone.title, .in_progress) } }
                                    Button("Completed") { Task { await setMilestoneStatus(inv.id, milestone.title, .completed) } }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .padding(10)
                    .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }
            }
        }
    }

    private func fieldLike(_ label: String, text: Binding<String>, placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if multiline {
                TextEditor(text: text)
                    .frame(height: 90)
                    .padding(8)
                    .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            } else {
                TextField(placeholder, text: text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }
        }
    }

    private func postEquityUpdate() async {
        guard let uid = auth.currentUserID, let first = activeEquityDealsForDashboard.first else { return }
        equityUpdateBusy = true
        defer { equityUpdateBusy = false }
        do {
            try await investmentService.postEquityVentureUpdate(
                investmentId: first.id,
                seekerId: uid,
                title: equityUpdateTitle,
                message: equityUpdateMessage,
                ventureStage: equityStage,
                growthMetric: equityGrowthMetric
            )
            equityUpdateTitle = ""
            equityUpdateMessage = ""
            equityGrowthMetric = ""
            await loadInvestments()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func setMilestoneStatus(_ investmentId: String, _ milestoneTitle: String, _ status: EquityMilestoneStatus) async {
        guard let uid = auth.currentUserID else { return }
        do {
            try await investmentService.updateEquityMilestoneStatus(
                investmentId: investmentId,
                seekerId: uid,
                milestoneTitle: milestoneTitle,
                status: status,
                note: nil
            )
            await loadInvestments()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private var singleInvestorDealCard: some View {
        let deal = primarySingleInvestorDeal
        let isCompleted = deal?.status.lowercased() == "completed"
        return sectionCard(
            title: isCompleted ? "Deal completed" : "Deal in progress",
            subtitle: isCompleted
                ? "This investment cycle is complete, but you can still coordinate in chat."
                : "Requests are closed after a deal is accepted",
            systemImage: "checkmark.seal.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let deal {
                    detailBlock(
                        title: "Current state",
                        value: deal.agreementStatus == .pending_signatures
                            ? "Awaiting signatures"
                            : deal.lifecycleDisplayTitle
                    )
                    if deal.status.lowercased() == "completed" {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                    Button {
                        agreementToReview = deal
                    } label: {
                        Text(deal.agreementStatus == .pending_signatures ? "Review & sign agreement" : "View agreement")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)

                    if deal.investorId != nil {
                        Button {
                            Task { await openChatWithInvestor(for: deal) }
                        } label: {
                            Label("Contact investor", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: AppTheme.minTapTarget)
                        }
                        .buttonStyle(.bordered)
                        .tint(auth.accentColor)
                    }
                } else {
                    Text("No active deal found yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        GeometryReader { geo in
            Group {
                if opportunity.imageStoragePaths.isEmpty {
                    RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: opportunity.effectiveVideoReference != nil ? "play.rectangle.fill" : "photo")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                        }
                } else {
                    AutoPagingImageCarousel(
                        references: opportunity.imageStoragePaths,
                        height: 240,
                        cornerRadius: AppTheme.cardCornerRadius
                    )
                }
            }
            .frame(width: geo.size.width, height: 240, alignment: .center)
            .clipped()
        }
        .frame(height: 240)
    }

    private func overviewCard(for o: OpportunityListing) -> some View {
        sectionCard(title: "", subtitle: nil, systemImage: nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(o.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let listed = o.createdAt {
                        Text(listed.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if !o.category.isEmpty {
                        Text(o.category)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    if o.verificationStatus == .verified {
                        tagPill(text: "Verified", icon: "checkmark.seal.fill", tint: .blue, filled: true)
                    }
                    tagPill(text: o.investmentType.displayName, icon: "chart.pie.fill", tint: .secondary)
                    Spacer(minLength: 0)
                }

                if !o.description.isEmpty {
                    Text(o.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func keyNumbersCard(for o: OpportunityListing) -> some View {
        sectionCard(title: "Key numbers", subtitle: "Same numbers investors see", systemImage: "chart.bar.fill") {
            let ticket = o.minimumInvestment
            let ticketText = (o.maximumInvestors ?? 1) <= 1
                ? "LKR \(o.formattedAmountLKR) (full round)"
                : "LKR \(o.formattedMinimumLKR) (min. ticket)"

            VStack(alignment: .leading, spacing: 12) {
                keyNumbersPrimaryMetric(for: o, ticket: ticket)
                switch o.investmentType {
                case .loan:
                    loanReturnsSnapshot(for: o, ticket: ticket, ticketText: ticketText)
                case .equity:
                    sectionCard(title: "Return snapshot", subtitle: nil, systemImage: nil) {
                        seekerEquityValueBody(o: o, ticket: ticket, ticketText: ticketText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func loanReturnsSnapshot(for o: OpportunityListing, ticket: Double, ticketText: String) -> some View {
        let t = o.terms
        if let rate = t.interestRate,
           let months = t.repaymentTimelineMonths, months > 0,
           ticket > 0,
           let preview = OpportunityFinancialPreview.loanMoneyOutcome(
               principal: ticket,
               annualRatePercent: rate,
               termMonths: months,
               plan: LoanRepaymentPlan.from(t.repaymentFrequency)
           ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount to be paid")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("LKR \(OpportunityFinancialPreview.formatLKRInteger(preview.totalRepayable))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Based on \(ticketText) over \(months) months.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
            )
            .appCardShadow()
        } else {
            seekerLoanValueBody(o: o, ticket: ticket, ticketText: ticketText)
        }
    }

    @ViewBuilder
    private func keyNumbersPrimaryMetric(for o: OpportunityListing, ticket: Double) -> some View {
        switch o.investmentType {
        case .loan:
            if let rate = o.terms.interestRate {
                if let months = o.terms.repaymentTimelineMonths, months > 0,
                   let preview = OpportunityFinancialPreview.loanMoneyOutcome(
                    principal: ticket,
                    annualRatePercent: rate,
                    termMonths: months,
                    plan: LoanRepaymentPlan.from(o.terms.repaymentFrequency)
                   ) {
                    HStack(spacing: 8) {
                        metricTile(title: "Interest rate", value: "\(formatRate(rate))%", tint: auth.accentColor)
                        metricTile(title: "Timeline", value: "\(months) mo", tint: .primary)
                        metricTile(title: "Final profit", value: OpportunityFinancialPreview.formatLKRInteger(preview.interestAmount), tint: .green)
                    }
                } else {
                    HStack(spacing: 8) {
                        metricTile(title: "Interest rate", value: "\(formatRate(rate))%", tint: auth.accentColor)
                        metricTile(title: "Timeline", value: "—", tint: .primary)
                    }
                }
            } else {
                placeholderPrimaryMetric(caption: "Rate not set")
            }
        case .equity:
            if let eq = o.terms.equityPercentage, eq > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(formatRate(eq))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(auth.accentColor)
                    Text("Equity offered (full round)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                placeholderPrimaryMetric(caption: "Equity %")
            }
        }
    }

    @ViewBuilder
    private func placeholderPrimaryMetric(caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("—")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func seekerLoanValueBody(o: OpportunityListing, ticket: Double, ticketText: String) -> some View {
        let t = o.terms
        if let rate = t.interestRate,
           let months = t.repaymentTimelineMonths, months > 0,
           ticket > 0,
           let preview = OpportunityFinancialPreview.loanMoneyOutcome(
               principal: ticket,
               annualRatePercent: rate,
               termMonths: months,
               plan: LoanRepaymentPlan.from(t.repaymentFrequency)
           ) {
            let freq = (t.repaymentFrequency ?? .monthly).displayName
            VStack(alignment: .leading, spacing: 8) {
                Text("Estimated return for \(ticketText): LKR \(OpportunityFinancialPreview.formatLKRInteger(preview.interestAmount)) interest over \(months) months.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let first = preview.firstInstallmentDue, let last = preview.maturityDue {
                    if first == last {
                        Text("One payment around \(OpportunityFinancialPreview.mediumDate(first)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Modeled \(freq) cadence: first installment about \(OpportunityFinancialPreview.mediumDate(first)), last by \(OpportunityFinancialPreview.mediumDate(last)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("Once this listing has a clear rate and timeline, projected profit and total return will appear here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func seekerEquityValueBody(o: OpportunityListing, ticket: Double, ticketText: String) -> some View {
        let t = o.terms
        if let eq = t.equityPercentage, eq > 0, o.amountRequested > 0, ticket > 0,
           let slice = OpportunityFinancialPreview.equitySlicePercent(
               roundEquityPercent: eq,
               investorAmount: ticket,
               goalAmount: o.amountRequested
           ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    compactMetric(title: "Round equity", value: "\(formatRate(eq))%")
                    compactMetric(title: "Estimated share", value: "\(formatRate(slice))%")
                    compactMetric(title: "Ticket", value: ticketText.replacingOccurrences(of: "LKR ", with: ""))
                }
                if let v = t.businessValuation, v > 0 {
                    compactMetric(title: "Valuation", value: OpportunityFinancialPreview.formatLKRInteger(v))
                }
            }
        } else {
            compactMetric(title: "Ownership estimate", value: "Awaiting complete inputs")
        }
    }

    @ViewBuilder
    private func seekerRevenueShareValueBody(o: OpportunityListing) -> some View {
        let t = o.terms
        if let p = t.revenueSharePercent, p > 0,
           let target = t.targetReturnAmount, target > 0 {
            let cap = t.maxDurationMonths.map { "\($0) months" } ?? "the agreed cap"
            Text("Investors share \(formatRate(p))% of revenue until LKR \(OpportunityFinancialPreview.formatLKRInteger(target)) is paid back (max \(cap)).")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Add revenue share %, target, and duration so backers can see the upside cap.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func seekerProjectValueBody(o: OpportunityListing) -> some View {
        let t = o.terms
        let kind = t.expectedReturnType?.rawValue.capitalized ?? "Return"
        let value = (t.expectedReturnValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(kind): \(value)")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = t.completionDate {
                    Text("Target wrap-up: \(Self.mediumDate(d)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Describe the expected return so investors can judge the upside.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func seekerCustomValueBody(o: OpportunityListing) -> some View {
        let s = (o.terms.customTermsSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty {
            Text(String(s.prefix(280)) + (s.count > 280 ? "…" : ""))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Custom summary will appear here once terms are completed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    private func incomeFundsTimelineCard(for o: OpportunityListing) -> some View {
        sectionCard(title: "Income, funds & timeline", subtitle: nil, systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 10) {
                detailBlock(
                    title: "Income generation method",
                    value: o.incomeGenerationMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not added yet" : o.incomeGenerationMethod
                )
                detailBlock(
                    title: "Use of funds",
                    value: o.useOfFunds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not added yet" : o.useOfFunds
                )
            }
        }
    }

    private func dealTermsCard(for o: OpportunityListing) -> some View {
        sectionCard(title: "Deal terms", subtitle: nil, systemImage: "doc.text.fill") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(termPairs(for: o), id: \.0) { pair in
                    HStack(alignment: .top, spacing: 8) {
                        Text(pair.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(pair.1)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func executionPlanCard(for o: OpportunityListing) -> some View {
        sectionCard(title: "Execution plan", subtitle: "Milestones from investment acceptance", systemImage: "list.bullet.rectangle.fill") {
            if !o.milestones.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(o.milestones.enumerated()), id: \.offset) { index, milestone in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(auth.accentColor)
                                    .frame(width: 10, height: 10)
                                if index < o.milestones.count - 1 {
                                    Rectangle()
                                        .fill(auth.accentColor.opacity(0.35))
                                        .frame(width: 2, height: 44)
                                }
                            }
                            .frame(width: 14)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(milestone.title.isEmpty ? "Milestone" : milestone.title)
                                    .font(.subheadline.weight(.semibold))
                                if let days = milestone.dueDaysAfterAcceptance {
                                    Text("+\(days) days from acceptance")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                } else if let expected = milestone.expectedDate {
                                    Text(Self.mediumDate(expected))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(auth.accentColor)
                                } else {
                                    Text("Date to be confirmed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.bottom, index < o.milestones.count - 1 ? 4 : 0)
                        }
                    }
                }
            } else {
                Text("No milestones added yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String?,
        systemImage: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    if let systemImage, !systemImage.isEmpty {
                        Image(systemName: systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(auth.accentColor)
                            .frame(width: 22, height: 22)
                            .background(auth.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
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
            }

            content()
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func tagPill(text: String, icon: String, tint: Color, small: Bool = false, filled: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(small ? .caption2 : .caption)
            Text(text)
                .font(small ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        }
        .padding(.horizontal, small ? 8 : 10)
        .padding(.vertical, small ? 5 : 7)
        .background(
            Group {
                if filled {
                    Capsule().fill(tint.opacity(0.14))
                } else {
                    Capsule().fill(AppTheme.secondaryFill)
                }
            }
        )
        .foregroundStyle(filled ? tint : .primary)
    }

    private func detailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    private func metricTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        )
    }

    private func termPairs(for o: OpportunityListing) -> [(String, String)] {
        let t = o.terms
        switch o.investmentType {
        case .loan:
            return [
                ("Interest", t.interestRate.map { "\(formatRate($0))%" } ?? "—"),
                ("Timeline", t.repaymentTimelineMonths.map { "\($0) months" } ?? "—"),
                ("Frequency", (t.repaymentFrequency ?? .monthly).displayName)
            ]
        case .equity:
            return [
                ("Equity %", t.equityPercentage.map { "\(formatRate($0))%" } ?? "—"),
                ("Valuation", t.businessValuation.map { "LKR \(formatAmount($0))" } ?? "—"),
                ("Exit plan", t.exitPlan?.isEmpty == false ? t.exitPlan! : "—")
            ]
        }
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(Int(rate))
        }
        return String(format: "%.1f", rate)
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private static func initials(from name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "I" }
        let parts = cleaned.split(whereSeparator: \.isWhitespace)
        if parts.count >= 2 {
            let a = parts[0].prefix(1)
            let b = parts[1].prefix(1)
            return (a + b).uppercased()
        }
        return String(cleaned.prefix(1)).uppercased()
    }

    private func requestRow(_ inv: InvestmentListing) -> some View {
        let pending = inv.status.lowercased() == "pending"
        let isOffer = inv.isOfferRequest
        let chromeTint: Color = isOffer ? .red : auth.accentColor
        let profile = inv.investorId.flatMap { investorProfilesById[$0] }
        let investorName = displayName(for: profile, investorId: inv.investorId)
        let displayAmount = inv.effectiveAmount
        let displayRate: String = {
            let value = inv.effectiveFinalInterestRate
            guard let value else { return "-" }
            return "\(formatRate(value))%"
        }()
        let displayTimeline: String = {
            let value = inv.effectiveFinalTimelineMonths
            guard let value else { return "-" }
            return "\(value) months"
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                seekerRequestAvatar(profile: profile, name: investorName)

                VStack(alignment: .leading, spacing: 4) {
                    Text(investorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(requestStatusLabel(for: inv))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(inv).opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor(inv))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("LKR \(formatAmount(displayAmount))")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("\(displayRate) • \(displayTimeline)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minWidth: 126, alignment: .trailing)
            }

            if inv.isOfferRequest {
                HStack(spacing: 8) {
                    Text("Offer")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.16), in: Capsule())
                        .foregroundStyle(.red)
                    if let source = inv.offerSource {
                        Text(source == .chat ? "From chat" : "From request sheet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            if inv.isOfferRequest {
                VStack(alignment: .leading, spacing: 4) {
                    let amount = inv.effectiveAmount
                    if amount > 0 {
                        Text("Offered amount: LKR \(formatAmount(amount))")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let rate = inv.effectiveFinalInterestRate, let months = inv.effectiveFinalTimelineMonths {
                        Text(String(format: "Offered terms: %.2f%% • %d months", rate, months))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let note = inv.offerDescription, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                    }
                }
            }

            if let investorId = inv.investorId {
                HStack(spacing: 10) {
                    NavigationLink {
                        PublicProfileView(
                            userId: investorId,
                            chatContext: .init(
                                opportunityId: opportunity.id,
                                seekerId: auth.currentUserID,
                                opportunityTitle: opportunity.title
                            )
                        )
                    } label: {
                        Label("Profile", systemImage: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)

                    Button {
                        Task { await openChatWithInvestor(for: inv) }
                    } label: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                }
            }

            if pending {
                VStack(spacing: 10) {
                    Button {
                        acceptingFor = inv
                    } label: {
                        Text("Accept")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(chromeTint)

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
                    .tint(.red)
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
                .tint(chromeTint)
            } else if inv.agreement != nil {
                Button {
                    agreementToReview = inv
                } label: {
                    Text("View agreement")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(chromeTint)
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
        .background(
            (isOffer ? Color.orange.opacity(0.07) : AppTheme.cardBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(
                    isOffer ? Color.orange.opacity(0.45) : Color(uiColor: .separator).opacity(0.45),
                    lineWidth: 1
                )
        )
        .appCardShadow()
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
            let rows = try await investmentService.fetchInvestmentsForOpportunity(opportunityId: opportunity.id)
            // Revoked requests are deleted in Firestore; hide legacy `withdrawn` rows so the sheet doesn’t show stuck cards without actions.
            let visible = rows.filter { $0.status.lowercased() != "withdrawn" }
            investments = visible
            investorProfilesById = await loadInvestorProfiles(for: visible)
            if !LoanRepaymentCalendarSync.hasCalendarSyncPreference,
               !showCalendarSyncPrompt,
               visible.contains(where: { $0.agreementStatus == .active }) {
                showCalendarSyncPrompt = true
            }
            if let uid = auth.currentUserID {
                for row in visible where row.agreementStatus == .active {
                    await LoanRepaymentCalendarSync.syncPostAgreementEvents(
                        investment: row,
                        opportunity: opportunity,
                        currentUserId: uid
                    )
                }
            }
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func loadInvestorProfiles(for rows: [InvestmentListing]) async -> [String: UserProfile] {
        let ids = Set(rows.compactMap(\.investorId))
        guard !ids.isEmpty else { return [:] }
        var out: [String: UserProfile] = [:]
        for id in ids {
            if let profile = try? await userService.fetchProfile(userID: id) {
                out[id] = profile
            }
        }
        return out
    }

    private func displayName(for profile: UserProfile?, investorId: String?) -> String {
        if let legal = profile?.profileDetails?.legalFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !legal.isEmpty {
            return legal
        }
        if let display = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        if let investorId {
            return "Investor \(shortId(investorId))"
        }
        return "Investor"
    }

    private func requestStatusLabel(for inv: InvestmentListing) -> String {
        if inv.status.lowercased() == "pending" {
            return inv.isOfferRequest ? "Offer pending" : "Pending decision"
        }
        return inv.lifecycleDisplayTitle
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
        case "pending": return inv.isOfferRequest ? .red : .orange
        case "accepted", "active": return .green
        case "declined", "rejected": return .red
        default: return .secondary
        }
    }

    private func openChatWithInvestor(for inv: InvestmentListing) async {
        guard let seekerId = auth.currentUserID else {
            actionSuccess = nil
            actionError = "Please sign in again."
            return
        }
        guard let investorId = inv.investorId, !investorId.isEmpty else {
            actionSuccess = nil
            actionError = "Could not identify this investor."
            return
        }
        do {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opportunity.id,
                seekerId: seekerId,
                investorId: investorId,
                opportunityTitle: opportunity.title
            )
            await MainActor.run {
                showReviewRequestsSheet = false
                acceptingFor = nil
                tabRouter.pendingChatDeepLink = ChatDeepLink(chatId: chatId, inquirySnapshot: nil)
                tabRouter.selectedTab = .chat
            }
        } catch {
            await MainActor.run {
                actionSuccess = nil
                actionError = (error as NSError).localizedDescription
            }
        }
    }

    @ViewBuilder
    private func seekerRequestAvatar(profile: UserProfile?, name: String) -> some View {
        let initials = Self.initials(from: name)
        let trimmed = profile?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ZStack {
            Circle()
                .fill(AppTheme.secondaryFill)
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let url = URL(string: trimmed), !trimmed.isEmpty {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: 40, height: 40)
    }

    private func decline(_ inv: InvestmentListing) async {
        guard let seekerId = auth.currentUserID else { return }
        actionSuccess = nil
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
