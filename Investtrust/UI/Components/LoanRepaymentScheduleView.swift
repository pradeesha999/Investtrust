import PhotosUI
import SwiftUI
import VisionKit

/// Full-screen loan repayment schedule: principal flow, live installments, and (when the deal is closed) a full payment history with dates.
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
    @State private var principalLibraryPickItem: PhotosPickerItem?
    @State private var isUpdatingPrincipal = false
    @State private var disputeInstallmentNo: Int?
    @State private var disputeReasonText = ""
    @State private var showPrincipalDisbursementSheet = false
    @State private var previewImageReference: String?
    @State private var showPrincipalNotReceivedSheet = false
    @State private var principalNotReceivedReasonText = ""
    @State private var showPaidInstallmentHistory = false

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

    /// One-line explainer for the party viewing this screen (reduces confusion between seeker vs investor steps).
    private var loanPaymentWorkflowFootnote: String? {
        guard investment.loanRepaymentsUnlocked, !isInvestmentCompleted else { return nil }
        guard let uid = currentUserId else { return nil }
        if uid == investment.seekerId {
            return "You pay each installment to the investor: attach a slip, then confirm you sent. They confirm it arrived."
        }
        if uid == investment.investorId {
            return "The seeker sends each installment and confirms first. Then you confirm receipt—or report if it didn’t arrive."
        }
        return nil
    }

    private var isInvestmentCompleted: Bool {
        investment.status.lowercased() == "completed" || investment.fundingStatus == .closed || (totalCount > 0 && confirmedCount == totalCount)
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var canOpenPrincipalDisbursement: Bool {
        investment.agreementStatus == .active || investment.fundingStatus != .none
    }

    /// Principal transfer / proof lives inline until the seeker confirms receipt and installments unlock.
    private var showEmbeddedPrincipalFlow: Bool {
        !investment.loanRepaymentsUnlocked && canOpenPrincipalDisbursement
    }

    /// After disbursement is confirmed, the same details move behind the bar button + sheet.
    private var showPrincipalDisbursementBarButton: Bool {
        investment.loanRepaymentsUnlocked && canOpenPrincipalDisbursement
    }

    /// Identity for `.task` so calendar reminders refresh when the schedule or agreement state changes.
    private var calendarSyncTaskId: String {
        let parts = investment.loanInstallments
            .sorted { $0.installmentNo < $1.installmentNo }
            .map { "\($0.installmentNo):\($0.status.rawValue)" }
        return "\(investment.id)|\(investment.agreementStatus.rawValue)|" + parts.joined(separator: ",")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                if showEmbeddedPrincipalFlow {
                    repaymentsLockedPrincipalIntro
                    principalDisbursementCard
                } else if !investment.loanRepaymentsUnlocked {
                    repaymentsLockedAwaitingAgreementCallout
                }

                if investment.loanRepaymentsUnlocked {
                    if isInvestmentCompleted {
                        closedDealSummaryCard
                    }
                    summaryHero
                    if !isInvestmentCompleted, loanPaymentWorkflowFootnote != nil {
                        Text(loanPaymentWorkflowFootnote!)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !isInvestmentCompleted {
                        scheduleSection(
                            title: "Installments",
                            subtitle: "One at a time, in due-date order",
                            systemImage: "calendar",
                            rows: openRows,
                            emptyMessage: "All installments are complete."
                        )
                    }

                    if isInvestmentCompleted {
                        closedDealPrincipalHistory
                        paymentHistorySection
                    } else if !completedRows.isEmpty {
                        DisclosureGroup(isExpanded: $showPaidInstallmentHistory) {
                            VStack(spacing: 10) {
                                ForEach(completedRows) { row in
                                    installmentCard(row)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Paid installments")
                                        .font(.headline)
                                    Text("\(completedRows.count) finished")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: [.horizontal, .bottom]))
        .navigationTitle("Loan repayments")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if showPrincipalDisbursementBarButton {
                Button {
                    showPrincipalDisbursementSheet = true
                } label: {
                    Label("Principal transfer", systemImage: "banknote.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.minTapTarget)
                }
                .buttonStyle(.plain)
                .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
            }
        }
        .task(id: calendarSyncTaskId) {
            await LoanRepaymentCalendarSync.syncIfEligible(
                investment: investment,
                currentUserId: auth.currentUserID
            )
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
        .sheet(isPresented: $showPrincipalNotReceivedSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tell the investor why the principal did not arrive (wrong account, amount mismatch, no credit, etc.). They can upload new proof and mark sent again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $principalNotReceivedReasonText)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    Text("This clears their “sent” status and current proof images for this round.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.screenPadding)
                .navigationTitle("Principal not received")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            principalNotReceivedReasonText = ""
                            showPrincipalNotReceivedSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send to investor") {
                            let t = principalNotReceivedReasonText
                            principalNotReceivedReasonText = ""
                            showPrincipalNotReceivedSheet = false
                            Task { await reportPrincipalNotReceived(reason: t) }
                        }
                        .disabled(principalNotReceivedReasonText.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
                    }
                }
            }
        }
        .sheet(isPresented: $showPrincipalDisbursementSheet) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    principalDisbursementCard
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.screenPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Principal transfer")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: Binding(
            get: { previewImageReference != nil },
            set: { if !$0 { previewImageReference = nil } }
        )) {
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let previewImageReference {
                        GeometryReader { geo in
                            StorageBackedAsyncImage(
                                reference: previewImageReference,
                                height: min(geo.size.height * 0.72, 560),
                                cornerRadius: 14,
                                feedThumbnail: false
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, AppTheme.screenPadding)
                        }
                    }
                }
                .navigationTitle("Proof image")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder
    private var repaymentsLockedPrincipalIntro: some View {
        let isInvestor = currentUserId == investment.investorId
        let isSeeker = currentUserId == investment.seekerId
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 36, alignment: .center)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Principal before installments")
                        .font(.headline.weight(.semibold))
                    Group {
                        if isInvestor {
                            Text("Add transfer proof, then mark sent. The seeker confirms receipt to unlock repayments.")
                        } else if isSeeker {
                            Text("When the money is in your account, confirm receipt below to unlock the schedule.")
                        } else {
                            Text("Principal transfer and confirmation happen here; installments appear after that.")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var repaymentsLockedAwaitingAgreementCallout: some View {
        ContentUnavailableView {
            Label("Repayments aren’t available yet", systemImage: "doc.text.fill")
        } description: {
            Text(
                "Complete and sign the investment agreement first. "
                    + "Principal transfer and confirmation will appear on this screen, then your installment schedule."
            )
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Closed deal (completed investment)

    private var closedDealSummaryCard: some View {
        let rateText: String? = {
            guard let r = investment.finalInterestRate else { return nil }
            let n = NSNumber(value: r)
            let f = NumberFormatter()
            f.maximumFractionDigits = 2
            f.minimumFractionDigits = 0
            return (f.string(from: n) ?? "\(r)") + "%"
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deal closed")
                        .font(.title3.weight(.bold))
                    Text("This loan is fully repaid and the investment is closed. Below is a record of principal, each installment, and the dates confirmations were recorded in the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                closedDealFactRow(title: "Loan principal", value: "LKR \(formatAmt(investment.investmentAmount))")
                if let rateText {
                    closedDealFactRow(title: "Interest rate (agreed)", value: rateText)
                }
                if let months = investment.finalTimelineMonths {
                    closedDealFactRow(title: "Term", value: "\(months) months")
                }
                closedDealFactRow(
                    title: "Total installment payments",
                    value: "LKR \(formatAmt(investment.confirmedLoanRepaymentTotal)) · \(confirmedCount) of \(totalCount) in schedule"
                )
                if let accepted = investment.acceptedAt {
                    closedDealFactRow(title: "Deal accepted", value: mediumDate(accepted))
                }
                if let updated = investment.updatedAt {
                    closedDealFactRow(title: "Record last updated", value: mediumDate(updated))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))

            Text("Investment ID: \(investment.id)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
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

    private func closedDealFactRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var closedDealPrincipalHistory: some View {
        let hasSent = investment.principalSentByInvestorAt != nil
        let hasReceived = investment.principalReceivedBySeekerAt != nil
        let hasProof = !investment.principalInvestorProofImageURLs.isEmpty || !investment.principalSeekerProofImageURLs.isEmpty
        if hasSent || hasReceived || hasProof {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "banknote")
                        .font(.headline)
                        .foregroundStyle(auth.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Principal transfer")
                            .font(.headline)
                        Text("How the loan amount reached the seeker before repayments started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let sent = investment.principalSentByInvestorAt {
                        historyDateRow(label: "Investor marked principal sent", date: sent)
                    }
                    if let received = investment.principalReceivedBySeekerAt {
                        historyDateRow(label: "Seeker confirmed principal received", date: received)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))

                let slipTitle = currentUserId == investment.seekerId ? "Your receiving proof" : (currentUserId == investment.investorId ? "Seeker receiving proof" : "Receiving proof")
                let outTitle = currentUserId == investment.investorId ? "Your transfer proof" : (currentUserId == investment.seekerId ? "Investor transfer proof" : "Transfer proof")
                if !investment.principalInvestorProofImageURLs.isEmpty || !investment.principalSeekerProofImageURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        if !investment.principalInvestorProofImageURLs.isEmpty {
                            proofThumbnailStrip(title: outTitle, urls: investment.principalInvestorProofImageURLs)
                        }
                        if !investment.principalSeekerProofImageURLs.isEmpty {
                            proofThumbnailStrip(title: slipTitle, urls: investment.principalSeekerProofImageURLs)
                        }
                    }
                }
            }
        }
    }

    private func historyDateRow(label: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(mediumDate(date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var paymentHistorySection: some View {
        if sorted.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.headline)
                        .foregroundStyle(auth.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installment payment history")
                            .font(.headline)
                        Text("Each row is one scheduled payment: amount, due date, and when each side confirmed in the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 10) {
                    ForEach(sorted) { row in
                        installmentHistoryCard(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func installmentHistoryCard(_ row: LoanInstallment) -> some View {
        let isSeeker = currentUserId == investment.seekerId
        let isInvestor = currentUserId == investment.investorId
        let slipProofTitle = isSeeker ? "Your payment slip" : (isInvestor ? "Seeker’s slip" : "Payment slip")
        let receiptProofTitle = isSeeker ? "Investor’s receipt" : (isInvestor ? "Your receipt" : "Receipt")
        let paid = row.status == .confirmed_paid

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Installment #\(row.installmentNo)")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                if paid {
                    Label("Paid", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    statusPill(row)
                }
            }

            Text("LKR \(formatAmt(row.totalDue))")
                .font(.title3.weight(.bold))
            Text("Principal LKR \(formatAmt(row.principalComponent)) · Interest LKR \(formatAmt(row.interestComponent))")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                historyDateRow(label: "Due date", date: row.dueDate)
                if let sent = row.seekerMarkedReceivedAt {
                    historyDateRow(label: "Seeker marked payment sent", date: sent)
                } else {
                    historyMissingRow(label: "Seeker marked payment sent")
                }
                if let received = row.investorMarkedPaidAt {
                    historyDateRow(label: "Investor confirmed payment received", date: received)
                } else {
                    historyMissingRow(label: "Investor confirmed payment received")
                }
                if paid, let s = row.seekerMarkedReceivedAt, let i = row.investorMarkedPaidAt {
                    let settled = max(s, i)
                    historyDateRow(label: "Fully settled in app (latest step)", date: settled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))

            installmentProofThumbnails(row, slipTitle: slipProofTitle, receiptTitle: receiptProofTitle)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
        )
        .appCardShadow()
    }

    private func historyMissingRow(label: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text("—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Summary

    private var summaryHero: some View {
        let progress = totalCount > 0 ? Double(confirmedCount) / Double(totalCount) : 0
        let confirmedTotal = sorted
            .filter { $0.status == .confirmed_paid }
            .reduce(0) { $0 + $1.totalDue }
        let confirmedPrincipal = sorted
            .filter { $0.status == .confirmed_paid }
            .reduce(0) { $0 + $1.principalComponent }
        let confirmedInterest = sorted
            .filter { $0.status == .confirmed_paid }
            .reduce(0) { $0 + $1.interestComponent }

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

            if confirmedCount > 0 {
                Text("Paid so far LKR \(formatAmt(confirmedTotal)) · principal \(formatAmt(confirmedPrincipal)) · interest \(formatAmt(confirmedInterest))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("All installments paid")
                        .font(.subheadline.weight(.semibold))
                    Text("Total repaid on schedule: LKR \(formatAmt(confirmedTotal)) (principal \(formatAmt(confirmedPrincipal)) · interest \(formatAmt(confirmedInterest))).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
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
            Text("Loan principal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            principalStatusChip

            if isInvestor,
               investment.fundingStatus == .awaiting_disbursement,
               let seekerNote = investment.principalSeekerNotReceivedReason,
               !seekerNote.isEmpty,
               investment.principalSentByInvestorAt == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Seeker reported: principal not received")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(seekerNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }

            if investment.fundingStatus == .disbursed, investment.principalReceivedBySeekerAt != nil {
                Label("Principal confirmed - repayments are now active", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }

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
                    VStack(spacing: 10) {
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

                        Button {
                            showPrincipalNotReceivedSheet = true
                        } label: {
                            Text("Principal not received")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(isUpdatingPrincipal)
                    }
                }
            }

            principalProofThumbnails

            if investment.agreementStatus == .active,
               (investment.fundingStatus == .awaiting_disbursement || investment.fundingStatus == .disbursed),
               canAttachPrincipalProof {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $principalLibraryPickItem, matching: .images) {
                        Label("Photos", systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                    .disabled(isUpdatingPrincipal)
                    .onChange(of: principalLibraryPickItem) { _, item in
                        guard let item else { return }
                        Task {
                            await handlePickedPhoto(item: item, target: .principalDisbursement)
                            await MainActor.run { principalLibraryPickItem = nil }
                        }
                    }

                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            proofUploadTarget = .principalDisbursement
                            showDocCamera = true
                        } label: {
                            Image(systemName: "doc.viewfinder")
                                .font(.title3)
                                .frame(width: 52, height: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(auth.accentColor)
                        .accessibilityLabel("Scan transfer proof")
                        .disabled(isUpdatingPrincipal)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .imageUploadProgressOverlay(isPresented: isUpdatingPrincipal, cornerRadius: AppTheme.cardCornerRadius)
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

    private func installmentWorkflowHint(
        row: LoanInstallment,
        isSeeker: Bool,
        isInvestor: Bool,
        isCurrentCycle: Bool
    ) -> String? {
        guard investment.loanRepaymentsUnlocked, row.status != .confirmed_paid else { return nil }
        if !isCurrentCycle {
            return "Finish installment #\(nextOpenRow?.installmentNo ?? 1) before this one."
        }
        if isSeeker {
            if row.seekerMarkedReceivedAt != nil {
                return "Waiting for the investor to confirm receipt."
            }
            return "Add a payment slip, then confirm you sent this installment."
        }
        if isInvestor {
            if row.investorMarkedPaidAt != nil { return nil }
            if row.seekerMarkedReceivedAt == nil {
                return "Waiting for the seeker to send this installment."
            }
            return "Confirm receipt when funds arrive—or report if they don’t."
        }
        return nil
    }

    @ViewBuilder
    private func installmentSettlementFootnote(_ row: LoanInstallment) -> some View {
        switch (row.seekerMarkedReceivedAt, row.investorMarkedPaidAt) {
        case let (s?, i?):
            Text("Payment sent \(mediumDate(s)) · Receipt confirmed \(mediumDate(i))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case let (s?, nil):
            Text("Payment sent \(mediumDate(s)) · awaiting investor confirmation")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case let (nil, i?):
            Text("Receipt confirmed \(mediumDate(i))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        default:
            Text("Fully paid")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func installmentCard(_ row: LoanInstallment) -> some View {
        let isInvestor = currentUserId == investment.investorId
        let isSeeker = currentUserId == investment.seekerId
        let overdue = row.status != .confirmed_paid && row.dueDate < startOfToday
        let isCurrentCycle = row.installmentNo == nextOpenRow?.installmentNo
        let slipProofTitle = isSeeker ? "Your payment slip" : (isInvestor ? "Seeker’s slip" : "Payment slip")
        let receiptProofTitle = isSeeker ? "Investor’s receipt" : (isInvestor ? "Your receipt" : "Receipt")

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
                Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if row.status == .confirmed_paid {
                installmentSettlementFootnote(row)
            } else if let hint = installmentWorkflowHint(
                row: row,
                isSeeker: isSeeker,
                isInvestor: isInvestor,
                isCurrentCycle: isCurrentCycle
            ) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if row.status == .disputed, let reason = row.latestDisputeReason, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Issue reported")
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

            installmentProofThumbnails(row, slipTitle: slipProofTitle, receiptTitle: receiptProofTitle)

            if row.status != .confirmed_paid, investment.loanRepaymentsUnlocked {
                let seekerReady = !row.seekerProofImageURLs.isEmpty || row.investorMarkedPaidAt != nil
                let seekerConfirmed = row.seekerMarkedReceivedAt != nil
                if isCurrentCycle {
                    if isSeeker, row.seekerMarkedReceivedAt == nil {
                        HStack(spacing: 10) {
                            InstallmentProofLibraryPicker(
                                isInvestor: false,
                                compact: true,
                                disabled: busyInstallment != nil,
                                accentColor: auth.accentColor,
                                onPicked: { item in
                                    await handlePickedPhoto(item: item, target: .installment(row.installmentNo))
                                }
                            )
                            if VNDocumentCameraViewController.isSupported {
                                Button {
                                    proofUploadTarget = .installment(row.installmentNo)
                                    showDocCamera = true
                                } label: {
                                    Image(systemName: "doc.viewfinder")
                                        .font(.title3)
                                        .frame(width: 52, height: 48)
                                }
                                .buttonStyle(.bordered)
                                .tint(auth.accentColor)
                                .accessibilityLabel("Scan payment slip")
                                .disabled(busyInstallment != nil)
                            }
                        }

                        Button {
                            Task { await markReceived(row.installmentNo) }
                        } label: {
                            Text("I sent this payment")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(auth.accentColor)
                        .disabled(busyInstallment != nil || !seekerReady)
                    }

                    if isInvestor, row.investorMarkedPaidAt == nil {
                        if seekerConfirmed {
                            HStack(spacing: 10) {
                                InstallmentProofLibraryPicker(
                                    isInvestor: true,
                                    compact: true,
                                    disabled: busyInstallment != nil,
                                    accentColor: auth.accentColor,
                                    onPicked: { item in
                                        await handlePickedPhoto(item: item, target: .installment(row.installmentNo))
                                    }
                                )
                                if VNDocumentCameraViewController.isSupported {
                                    Button {
                                        proofUploadTarget = .installment(row.installmentNo)
                                        showDocCamera = true
                                    } label: {
                                        Image(systemName: "doc.viewfinder")
                                            .font(.title3)
                                            .frame(width: 52, height: 48)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(auth.accentColor)
                                    .accessibilityLabel("Scan receipt")
                                    .disabled(busyInstallment != nil)
                                }
                            }

                            Button {
                                Task { await markPaid(row.installmentNo) }
                            } label: {
                                Text("I received this payment")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(auth.accentColor)
                            .disabled(busyInstallment != nil)

                            Button {
                                disputeReasonText = row.latestDisputeReason ?? ""
                                disputeInstallmentNo = row.installmentNo
                            } label: {
                                Text("I didn’t receive it")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .disabled(busyInstallment != nil)
                        }
                    }
                } else {
                    Text("Finish installment #\(nextOpenRow?.installmentNo ?? 1) first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if !investment.loanRepaymentsUnlocked {
                Label("Unlocks after principal is confirmed", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
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
        .imageUploadProgressOverlay(isPresented: busyInstallment == row.installmentNo, cornerRadius: AppTheme.cardCornerRadius)
        .appCardShadow()
    }

    @ViewBuilder
    private func installmentProofThumbnails(_ row: LoanInstallment, slipTitle: String, receiptTitle: String) -> some View {
        let hasAny = !row.seekerProofImageURLs.isEmpty || !row.investorProofImageURLs.isEmpty
        if !hasAny {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !row.seekerProofImageURLs.isEmpty {
                    proofThumbnailStrip(title: slipTitle, urls: row.seekerProofImageURLs)
                }
                if !row.investorProofImageURLs.isEmpty {
                    proofThumbnailStrip(title: receiptTitle, urls: row.investorProofImageURLs)
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
                    proofThumbnailStrip(title: "Transfer out", urls: investment.principalInvestorProofImageURLs)
                }
                if !investment.principalSeekerProofImageURLs.isEmpty {
                    proofThumbnailStrip(title: "Received", urls: investment.principalSeekerProofImageURLs)
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
                        Button {
                            previewImageReference = url
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                StorageBackedAsyncImage(reference: url, height: 96, cornerRadius: 12, feedThumbnail: true)
                                    .frame(width: 96, height: 96)
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
            .scrollIndicators(.hidden)
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

    private func statusLabel(_ row: LoanInstallment) -> String {
        switch row.status {
        case .scheduled: return "Scheduled"
        case .awaiting_confirmation: return "Pending"
        case .confirmed_paid: return "Paid"
        case .disputed: return "Needs attention"
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

    private func reportPrincipalNotReceived(reason: String) async {
        guard let uid = currentUserId else { return }
        isUpdatingPrincipal = true
        defer { isUpdatingPrincipal = false }
        do {
            try await service.reportPrincipalNotReceivedBySeeker(
                investmentId: investment.id,
                userId: uid,
                reason: reason
            )
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
            return "Awaiting signatures"
        case .awaiting_disbursement:
            if let reason = investment.principalSeekerNotReceivedReason,
               !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               investment.principalSentByInvestorAt == nil {
                return "Seeker reported not received — upload new proof"
            }
            if let sent = investment.principalSentByInvestorAt {
                return "Sent \(mediumDate(sent)) · awaiting seeker confirmation"
            }
            return "Action required: mark principal sent"
        case .disbursed:
            if let received = investment.principalReceivedBySeekerAt {
                return "Confirmed \(mediumDate(received))"
            }
            return "Principal confirmed"
        case .defaulted:
            return "Loan defaulted"
        case .closed:
            return "Deal closed"
        }
    }

    private var principalStatusTint: Color {
        switch investment.fundingStatus {
        case .none: return .blue
        case .awaiting_disbursement:
            if investment.principalSeekerNotReceivedReason != nil,
               investment.principalSentByInvestorAt == nil {
                return .orange
            }
            return investment.principalSentByInvestorAt == nil ? auth.accentColor : .orange
        case .disbursed: return .green
        case .defaulted: return .red
        case .closed: return .secondary
        }
    }

    private var principalStatusChip: some View {
        Label(principalStatusText, systemImage: "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(principalStatusTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(principalStatusTint.opacity(0.14), in: Capsule())
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

/// One-tap photo library access for installment proof (no intermediate sheet).
private struct InstallmentProofLibraryPicker: View {
    let isInvestor: Bool
    var compact: Bool = false
    let disabled: Bool
    let accentColor: Color
    let onPicked: (PhotosPickerItem) async -> Void

    @State private var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            if compact {
                Label("Photos", systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            } else {
                Label(
                    isInvestor ? "Upload receipt proof from photos" : "Upload payment slip from photos",
                    systemImage: "photo"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(accentColor)
        .disabled(disabled)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                await onPicked(item)
                await MainActor.run { selection = nil }
            }
        }
    }
}
