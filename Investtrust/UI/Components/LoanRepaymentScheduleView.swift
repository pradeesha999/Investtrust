import PhotosUI
import SwiftUI
import VisionKit

/// Full-screen loan repayment schedule: separates open/upcoming from completed, with actions and proof upload.
struct LoanRepaymentScheduleView: View {
    private enum ProofUploadTarget: Equatable {
        case installment(Int)
        case principalDisbursement
    }

    let investment: InvestmentListing
    var currentUserId: String?
    var onRefresh: () async -> Void

    @Environment(AuthService.self) private var auth

    @State private var busyInstallment: Int?
    @State private var actionError: String?
    @State private var showDocCamera = false
    @State private var proofUploadTarget: ProofUploadTarget?
    @State private var showLibrarySheet = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var libraryUploadTarget: ProofUploadTarget?
    @State private var isUpdatingPrincipal = false
    @State private var disputeInstallmentNo: Int?
    @State private var disputeReasonText = ""

    private let service = InvestmentService()

    private var sorted: [LoanInstallment] {
        investment.loanInstallments.sorted { $0.installmentNo < $1.installmentNo }
    }

    private var openRows: [LoanInstallment] {
        sorted.filter { $0.status != .confirmed_paid }
    }

    private var completedRows: [LoanInstallment] {
        sorted.filter { $0.status == .confirmed_paid }.reversed()
    }

    private var confirmedCount: Int {
        sorted.filter { $0.status == .confirmed_paid }.count
    }

    private var totalCount: Int { sorted.count }

    private var nextOpenRow: LoanInstallment? {
        openRows.min(by: { $0.dueDate < $1.dueDate })
    }

    private var isInvestmentCompleted: Bool {
        investment.status.lowercased() == "completed" || investment.fundingStatus == .closed || (totalCount > 0 && confirmedCount == totalCount)
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Identity for `.task` so calendar reminders refresh when the schedule or agreement state changes.
    private var calendarSyncTaskId: String {
        let parts = investment.loanInstallments
            .sorted { $0.installmentNo < $1.installmentNo }
            .map { "\($0.installmentNo):\($0.status.rawValue)" }
        return "\(investment.id)|\(investment.agreementStatus.rawValue)|" + parts.joined(separator: ",")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                principalDisbursementCard
                if investment.loanRepaymentsUnlocked {
                    if isInvestmentCompleted {
                        completionCard
                    }
                    summaryHero
                    if !isInvestmentCompleted {
                        scheduleSection(
                            title: "Upcoming & open",
                            subtitle: "Installments still in progress",
                            systemImage: "calendar.badge.clock",
                            rows: openRows,
                            emptyMessage: "All installments are complete."
                        )
                    }

                    scheduleSection(
                        title: "Past & paid",
                        subtitle: "Fully confirmed repayments",
                        systemImage: "checkmark.seal.fill",
                        rows: completedRows,
                        emptyMessage: "No completed installments yet."
                    )
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Repayments")
        .navigationBarTitleDisplayMode(.large)
        .task(id: calendarSyncTaskId) {
            await LoanRepaymentCalendarSync.syncIfEligible(
                investment: investment,
                currentUserId: auth.currentUserID
            )
        }
        .sheet(isPresented: $showLibrarySheet) {
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Attach a receipt or transfer screenshot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle.angled")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                }
                .padding(AppTheme.screenPadding)
                .navigationTitle("Payment proof")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            libraryItem = nil
                            libraryUploadTarget = nil
                            showLibrarySheet = false
                        }
                    }
                }
                .onChange(of: libraryItem) { _, item in
                    guard let item, let target = libraryUploadTarget else { return }
                    libraryUploadTarget = nil
                    showLibrarySheet = false
                    Task {
                        await handlePickedPhoto(item: item, target: target)
                        await MainActor.run { libraryItem = nil }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showDocCamera) {
            Group {
                if VNDocumentCameraViewController.isSupported {
                    DocumentCameraView { images in
                        showDocCamera = false
                        guard let target = proofUploadTarget else { return }
                        proofUploadTarget = nil
                        Task {
                            await uploadProofJPEGChunks(images, target: target)
                        }
                    }
                } else {
                    NavigationStack {
                        ContentUnavailableView(
                            "Scanner unavailable",
                            systemImage: "doc.viewfinder",
                            description: Text("Document scanning isn’t supported on this device.")
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    showDocCamera = false
                                    proofUploadTarget = nil
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .sheet(isPresented: Binding(
            get: { disputeInstallmentNo != nil },
            set: { if !$0 { disputeInstallmentNo = nil } }
        )) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tell the seeker why this installment could not be confirmed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $disputeReasonText)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    Text("They must upload proof again and re-confirm this installment.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.screenPadding)
                .navigationTitle("Payment not received")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            disputeReasonText = ""
                            disputeInstallmentNo = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            guard let installmentNo = disputeInstallmentNo else { return }
                            let reason = disputeReasonText
                            disputeReasonText = ""
                            disputeInstallmentNo = nil
                            Task { await markNotReceived(installmentNo, reason: reason) }
                        }
                        .disabled(disputeReasonText.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Investment completed")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("All repayment cycles are confirmed and this investment is now closed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .appCardShadow()
    }

    private var summaryHero: some View {
        let progress = totalCount > 0 ? Double(confirmedCount) / Double(totalCount) : 0

        return VStack(alignment: .leading, spacing: 14) {
            Text(investment.opportunityTitle.isEmpty ? "Investment" : investment.opportunityTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Progress")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(confirmedCount) of \(totalCount) paid")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .tint(auth.accentColor)
            }

            if let next = nextOpenRow {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(auth.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next due")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(mediumDate(next.dueDate)) · LKR \(formatAmt(next.totalDue))")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            } else if isInvestmentCompleted {
                Text("No pending installments.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private var principalDisbursementCard: some View {
        let isInvestor = currentUserId == investment.investorId
        let isSeeker = currentUserId == investment.seekerId
        return VStack(alignment: .leading, spacing: 10) {
            Text("Principal disbursement")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(principalStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if investment.fundingStatus == .awaiting_disbursement {
                if isInvestor, investment.principalSentByInvestorAt == nil {
                    Button {
                        Task { await markPrincipalSent() }
                    } label: {
                        Text("Mark principal sent")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                    .disabled(isUpdatingPrincipal || investment.principalInvestorProofImageURLs.isEmpty)
                } else if isSeeker, investment.principalSentByInvestorAt != nil, investment.principalReceivedBySeekerAt == nil {
                    Button {
                        Task { await confirmPrincipalReceived() }
                    } label: {
                        Text("Confirm principal received")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                    .disabled(isUpdatingPrincipal)
                }
            }

            principalProofThumbnails

            if investment.agreementStatus == .active,
               (investment.fundingStatus == .awaiting_disbursement || investment.fundingStatus == .disbursed),
               canAttachPrincipalProof {
                Menu {
                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            proofUploadTarget = .principalDisbursement
                            showDocCamera = true
                        } label: {
                            Label("Scan principal proof", systemImage: "doc.viewfinder")
                        }
                    }
                    Button {
                        libraryUploadTarget = .principalDisbursement
                        showLibrarySheet = true
                    } label: {
                        Label("Principal proof from photos", systemImage: "photo")
                    }
                } label: {
                    Label("Attach principal proof", systemImage: "paperclip")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(auth.accentColor)
                .disabled(isUpdatingPrincipal)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    // MARK: - Sections

    private func scheduleSection(
        title: String,
        subtitle: String,
        systemImage: String,
        rows: [LoanInstallment],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(auth.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if rows.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.cardPadding)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        installmentCard(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func installmentCard(_ row: LoanInstallment) -> some View {
        let isInvestor = currentUserId == investment.investorId
        let isSeeker = currentUserId == investment.seekerId
        let overdue = row.status != .confirmed_paid && row.dueDate < startOfToday
        let isCurrentCycle = row.installmentNo == nextOpenRow?.installmentNo

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("#\(row.installmentNo)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(auth.accentColor, in: Capsule())

                VStack(alignment: .leading, spacing: 4) {
                    Text("LKR \(formatAmt(row.totalDue))")
                        .font(.title3.weight(.bold))
                    Text("Due \(mediumDate(row.dueDate))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                statusPill(row)
            }

            if overdue {
                Label("Overdue — please update payment status", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if row.status != .confirmed_paid && isCurrentCycle {
                Text("Current cycle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(auth.accentColor)
            }

            if let sr = row.seekerMarkedReceivedAt {
                metaLine("Seeker confirmed payment sent", mediumDate(sr))
            }
            if let ip = row.investorMarkedPaidAt {
                metaLine("Investor confirmed receipt", mediumDate(ip))
            }
            if !row.seekerProofImageURLs.isEmpty {
                metaLine("Seeker proof", "\(row.seekerProofImageURLs.count) file(s)")
            }
            if !row.investorProofImageURLs.isEmpty {
                metaLine("Investor proof", "\(row.investorProofImageURLs.count) file(s)")
            }

            installmentProofThumbnails(row)
            if row.status == .disputed, let reason = row.latestDisputeReason, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Investor reported not received")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }

            if row.status != .confirmed_paid, investment.loanRepaymentsUnlocked {
                let seekerReady = !row.seekerProofImageURLs.isEmpty || row.investorMarkedPaidAt != nil
                let seekerConfirmed = row.seekerMarkedReceivedAt != nil
                if isCurrentCycle {
                    HStack(spacing: 10) {
                        if isSeeker, row.seekerMarkedReceivedAt == nil {
                            Button {
                                Task { await markReceived(row.installmentNo) }
                            } label: {
                                Text("Confirm payment sent")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(auth.accentColor)
                            .disabled(busyInstallment != nil || !seekerReady)
                        }
                        if isInvestor, row.investorMarkedPaidAt == nil {
                            VStack(spacing: 8) {
                                Button {
                                    Task { await markPaid(row.installmentNo) }
                                } label: {
                                    Text("Confirm payment received")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(auth.accentColor)
                                .disabled(busyInstallment != nil || !seekerConfirmed)

                                Button {
                                    disputeReasonText = row.latestDisputeReason ?? ""
                                    disputeInstallmentNo = row.installmentNo
                                } label: {
                                    Text("Report not received")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                .disabled(busyInstallment != nil || !seekerConfirmed)
                            }
                        }
                    }

                    if (isSeeker && row.seekerMarkedReceivedAt == nil) || (isInvestor && row.investorMarkedPaidAt == nil) {
                        Menu {
                            if VNDocumentCameraViewController.isSupported {
                                Button {
                                    proofUploadTarget = .installment(row.installmentNo)
                                    showDocCamera = true
                                } label: {
                                    Label(isInvestor ? "Scan receipt with camera" : "Scan slip with camera", systemImage: "doc.viewfinder")
                                }
                            }
                            Button {
                                libraryUploadTarget = .installment(row.installmentNo)
                                showLibrarySheet = true
                            } label: {
                                Label(isInvestor ? "Receipt from photos" : "Slip from photos", systemImage: "photo")
                            }
                        } label: {
                            Label(isInvestor ? "Attach receipt proof" : "Attach payment slip", systemImage: "paperclip")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(auth.accentColor)
                    }
                } else {
                    Text("Complete installment #\(nextOpenRow?.installmentNo ?? 1) before updating this one.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if !investment.loanRepaymentsUnlocked {
                Text("Actions unlock after principal disbursement is confirmed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isCurrentCycle && row.status != .confirmed_paid ? auth.accentColor.opacity(0.55) : Color(uiColor: .separator).opacity(0.35),
                    lineWidth: isCurrentCycle && row.status != .confirmed_paid ? 1.5 : 1
                )
        )
        .appCardShadow()
    }

    @ViewBuilder
    private func installmentProofThumbnails(_ row: LoanInstallment) -> some View {
        let hasAny = !row.seekerProofImageURLs.isEmpty || !row.investorProofImageURLs.isEmpty
        if !hasAny {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !row.seekerProofImageURLs.isEmpty {
                    proofThumbnailStrip(title: "Seeker payment proof", urls: row.seekerProofImageURLs)
                }
                if !row.investorProofImageURLs.isEmpty {
                    proofThumbnailStrip(title: "Investor receipt proof", urls: row.investorProofImageURLs)
                }
            }
        }
    }

    @ViewBuilder
    private var principalProofThumbnails: some View {
        let hasAny = !investment.principalInvestorProofImageURLs.isEmpty || !investment.principalSeekerProofImageURLs.isEmpty
        if hasAny {
            VStack(alignment: .leading, spacing: 8) {
                if !investment.principalInvestorProofImageURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(investment.principalInvestorProofImageURLs, id: \.self) { url in
                                StorageBackedAsyncImage(reference: url, height: 80, cornerRadius: 10, feedThumbnail: true)
                                    .frame(width: 80, height: 80)
                            }
                        }
                    }
                }
                if !investment.principalSeekerProofImageURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(investment.principalSeekerProofImageURLs, id: \.self) { url in
                                StorageBackedAsyncImage(reference: url, height: 80, cornerRadius: 10, feedThumbnail: true)
                                    .frame(width: 80, height: 80)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func proofThumbnailStrip(title: String, urls: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        StorageBackedAsyncImage(reference: url, height: 80, cornerRadius: 10, feedThumbnail: true)
                            .frame(width: 80, height: 80)
                    }
                }
            }
        }
    }

    private func statusPill(_ row: LoanInstallment) -> some View {
        Text(statusLabel(row))
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor(row).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(row))
    }

    private func metaLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusLabel(_ row: LoanInstallment) -> String {
        switch row.status {
        case .scheduled: return "Scheduled"
        case .awaiting_confirmation: return "Awaiting confirmation"
        case .confirmed_paid: return "Paid"
        case .disputed: return "Disputed"
        }
    }

    private func statusColor(_ row: LoanInstallment) -> Color {
        switch row.status {
        case .confirmed_paid: return .green
        case .awaiting_confirmation: return .orange
        case .disputed: return .red
        case .scheduled: return .secondary
        }
    }

    private func markPaid(_ no: Int) async {
        guard let uid = currentUserId else { return }
        busyInstallment = no
        defer { busyInstallment = nil }
        do {
            try await service.markLoanInstallmentPaidByInvestor(investmentId: investment.id, installmentNo: no, userId: uid)
            await onRefresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func markPrincipalSent() async {
        guard let uid = currentUserId else { return }
        isUpdatingPrincipal = true
        defer { isUpdatingPrincipal = false }
        do {
            try await service.markPrincipalSentByInvestor(investmentId: investment.id, userId: uid)
            await onRefresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func confirmPrincipalReceived() async {
        guard let uid = currentUserId else { return }
        isUpdatingPrincipal = true
        defer { isUpdatingPrincipal = false }
        do {
            try await service.confirmPrincipalReceivedBySeeker(investmentId: investment.id, userId: uid)
            await onRefresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func markReceived(_ no: Int) async {
        guard let uid = currentUserId else { return }
        busyInstallment = no
        defer { busyInstallment = nil }
        do {
            try await service.markLoanInstallmentReceivedBySeeker(investmentId: investment.id, installmentNo: no, userId: uid)
            await onRefresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func markNotReceived(_ no: Int, reason: String) async {
        guard let uid = currentUserId else { return }
        busyInstallment = no
        defer { busyInstallment = nil }
        do {
            try await service.markLoanInstallmentNotReceivedByInvestor(
                investmentId: investment.id,
                installmentNo: no,
                userId: uid,
                reason: reason
            )
            await onRefresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func handlePickedPhoto(item: PhotosPickerItem, target: ProofUploadTarget) async {
        guard let uid = currentUserId else { return }
        if case let .installment(installmentNo) = target {
            busyInstallment = installmentNo
        } else {
            isUpdatingPrincipal = true
        }
        defer { busyInstallment = nil }
        defer { isUpdatingPrincipal = false }
        guard let raw = try? await item.loadTransferable(type: Data.self), !raw.isEmpty else {
            await MainActor.run {
                actionError = "Couldn’t read that photo. Try another image or take a new picture."
            }
            return
        }
        let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: raw)
        guard !jpeg.isEmpty else {
            await MainActor.run {
                actionError = "Couldn’t convert that photo. Try another image."
            }
            return
        }
        do {
            switch target {
            case .installment(let installmentNo):
                try await service.attachLoanInstallmentProof(
                    investmentId: investment.id,
                    installmentNo: installmentNo,
                    userId: uid,
                    imageJPEG: jpeg
                )
            case .principalDisbursement:
                try await service.attachPrincipalDisbursementProof(
                    investmentId: investment.id,
                    userId: uid,
                    imageJPEG: jpeg
                )
            }
            await onRefresh()
        } catch {
            await MainActor.run {
                actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
            }
        }
    }

    private func uploadProofJPEGChunks(_ chunks: [Data], target: ProofUploadTarget) async {
        guard let uid = currentUserId else { return }
        for chunk in chunks {
            switch target {
            case .installment(let installmentNo):
                busyInstallment = installmentNo
            case .principalDisbursement:
                isUpdatingPrincipal = true
            }
            let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: chunk)
            guard !jpeg.isEmpty else {
                await MainActor.run {
                    actionError = "Couldn’t read a scanned page. Try scanning again."
                }
                continue
            }
            do {
                switch target {
                case .installment(let installmentNo):
                    try await service.attachLoanInstallmentProof(
                        investmentId: investment.id,
                        installmentNo: installmentNo,
                        userId: uid,
                        imageJPEG: jpeg
                    )
                case .principalDisbursement:
                    try await service.attachPrincipalDisbursementProof(
                        investmentId: investment.id,
                        userId: uid,
                        imageJPEG: jpeg
                    )
                }
            } catch {
                await MainActor.run {
                    actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
                }
            }
        }
        busyInstallment = nil
        isUpdatingPrincipal = false
        await onRefresh()
    }

    private func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func formatAmt(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }

    private var principalStatusText: String {
        switch investment.fundingStatus {
        case .none:
            return "Principal transfer starts after signatures are complete."
        case .awaiting_disbursement:
            if let sent = investment.principalSentByInvestorAt {
                return "Investor marked sent on \(mediumDate(sent)). Waiting for seeker confirmation."
            }
            return "Attach proof, then mark principal as sent."
        case .disbursed:
            if let received = investment.principalReceivedBySeekerAt {
                return "Principal confirmed on \(mediumDate(received)). Installments unlocked."
            }
            return "Principal completed."
        case .defaulted:
            return "This loan is flagged as defaulted due to overdue installments."
        case .closed:
            return "Principal and installment lifecycle are fully closed."
        }
    }

    private var canAttachPrincipalProof: Bool {
        guard investment.principalReceivedBySeekerAt == nil else { return false }
        if currentUserId == investment.investorId {
            return investment.principalInvestorProofImageURLs.isEmpty
        }
        if currentUserId == investment.seekerId {
            return investment.principalSeekerProofImageURLs.isEmpty
        }
        return false
    }
}
