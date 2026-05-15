import SwiftUI

// Investor-facing opportunity detail screen.
// Shows listing media, key financials, MOA status, and the "Contact seeker" and "Invest" actions.
struct OpportunityDetailView: View {
    let opportunityId: String

    @State private var opportunity: OpportunityListing?
    @State private var loadError: String?

    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    private let chatService = ChatService()
    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()
    private let userService = UserService()

    @State private var userProfileLoaded: UserProfile?
    @State private var sellerProfile: UserProfile?
    @State private var sellerProfileLoading = false
    @State private var showProfileEdit = false
    @State private var showCalendarSyncPrompt = false

    @State private var contactError: String?
    @State private var showContactError = false
    @State private var requestActionError: String?
    @State private var showRequestActionError = false
    @State private var showRequestSuccess = false
    @State private var isOpeningChat = false
    @State private var myLatestRequest: InvestmentListing?
    @State private var showInvestSheet = false
    @State private var showOfferSheet = false
    @State private var isRevokingRequest = false
    @State private var agreementReviewContext: AgreementReviewContext?

    private struct AgreementReviewContext: Identifiable {
        var id: String { investment.id }
        let investment: InvestmentListing
        let opportunity: OpportunityListing
    }

    private enum InvestorPrincipalTopBannerMode {
        case none
        case mustSendPrincipalAndProof
        case awaitingSeekerReceiptConfirmation
    }

    // Production path: load from Firestore by id (avoids `NavigationLink(value:)` / `Hashable` mismatches in lists).
    init(opportunityId: String) {
        self.opportunityId = opportunityId
    }

    // Preview / tests: optional seed while network loads.
    init(opportunity: OpportunityListing) {
        opportunityId = opportunity.id
        _opportunity = State(initialValue: opportunity)
    }

    var body: some View {
        Group {
            if let opportunity {
                detailContent(opportunity)
            } else if let loadError {
                StatusBlock(
                    icon: "exclamationmark.triangle.fill",
                    title: "Couldn’t load this listing",
                    message: loadError,
                    iconColor: .orange
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Opportunity")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could not open chat", isPresented: $showContactError) {
            Button("OK") { contactError = nil }
        } message: {
            Text(contactError ?? "")
        }
        .alert("Could not update request", isPresented: $showRequestActionError) {
            Button("OK") { requestActionError = nil }
        } message: {
            Text(requestActionError ?? "")
        }
        .alert("Request sent", isPresented: $showRequestSuccess) {
            Button("OK") {}
        } message: {
            Text("Your investment request has been sent to the seeker.")
        }
        .task(id: opportunityId) {
            await loadOpportunityFromServer()
        }
        .sheet(isPresented: $showInvestSheet) {
            if let opportunity, let uid = auth.currentUserID {
                InvestProposalSheet(
                    opportunity: opportunity,
                    investorId: uid,
                    preferOfferMode: opportunity.isNegotiable,
                    lockToStandardMode: !opportunity.isNegotiable
                ) {
                    handleProposalSubmitted(for: opportunity)
                }
            }
        }
        .sheet(isPresented: $showOfferSheet) {
            if let opportunity, let uid = auth.currentUserID {
                InvestProposalSheet(
                    opportunity: opportunity,
                    investorId: uid,
                    preferOfferMode: true,
                    lockToOfferMode: true
                ) {
                    handleProposalSubmitted(for: opportunity)
                }
            }
        }
        .sheet(item: $agreementReviewContext) { ctx in
            NavigationStack {
                InvestmentAgreementReviewView(
                    investment: ctx.investment,
                    canSign: ctx.investment.needsInvestorSignature(currentUserId: auth.currentUserID),
                    onSign: { signaturePNG in
                        guard let uid = auth.currentUserID else {
                            throw InvestmentService.InvestmentServiceError.notSignedIn
                        }
                        do {
                            try await investmentService.signAgreement(
                                investmentId: ctx.investment.id,
                                userId: uid,
                                signaturePNG: signaturePNG
                            )
                            await loadMyRequest(for: ctx.opportunity)
                        } catch {
                            await loadMyRequest(for: ctx.opportunity)
                            throw error
                        }
                    }
                )
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
                    }
                    if let opportunity, let uid = auth.currentUserID, let latest = myLatestRequest {
                        await LoanRepaymentCalendarSync.syncPostAgreementEvents(
                            investment: latest,
                            opportunity: opportunity,
                            currentUserId: uid
                        )
                    }
                }
            }
        } message: {
            Text("Investtrust can add repayment and milestone reminders for active deals.")
        }
        .sheet(isPresented: $showProfileEdit) {
            NavigationStack {
                ProfileEditView()
            }
        }
        .onChange(of: showProfileEdit) { _, isPresented in
            if !isPresented {
                Task { await loadUserProfile() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let opportunity {
                floatingActionBar(for: opportunity)
            }
        }
    }

    private var profileReadyForInvesting: Bool {
        userProfileLoaded?.profileDetails?.isCompleteForInvesting == true
    }

    private var investorPrincipalTopBannerMode: InvestorPrincipalTopBannerMode {
        guard let req = myLatestRequest, let uid = auth.currentUserID else { return .none }
        guard req.investorId == uid else { return .none }
        guard req.investmentType == .loan else { return .none }
        guard req.fundingStatus == .awaiting_disbursement else { return .none }
        let s = req.status.lowercased()
        guard req.agreementStatus == .active || s == "active" else { return .none }
        if req.principalSentByInvestorAt == nil {
            return .mustSendPrincipalAndProof
        }
        if req.principalReceivedBySeekerAt == nil {
            return .awaitingSeekerReceiptConfirmation
        }
        return .none
    }

    @ViewBuilder
    private func detailContent(_ opportunity: OpportunityListing) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if investorPrincipalTopBannerMode != .none {
                    investorPrincipalTopBanner
                        .padding(.horizontal, AppTheme.screenPadding)
                }

                heroSection(for: opportunity)
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.top, 8)

                overviewSection(for: opportunity)
                    .padding(.horizontal, AppTheme.screenPadding)

                if auth.currentUserID != opportunity.ownerId {
                    keyNumbersSection(for: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                }

                if shouldShowStatusCard(for: opportunity) {
                    statusCard(for: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                }
                if let req = myLatestRequest, req.agreement != nil {
                    agreementAccessCard(for: req, opportunity: opportunity)
                        .padding(.horizontal, AppTheme.screenPadding)
                }

                if let req = myLatestRequest,
                   req.investmentType == .equity,
                   req.agreementStatus == .active || req.status.lowercased() == "active" {
                    infoCard(title: "Venture updates", subtitle: "Latest progress from seeker", systemImage: "chart.line.uptrend.xyaxis") {
                        investorEquityUpdatesContent(req)
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                }

                if let req = myLatestRequest, req.isLoanWithSchedule {
                    LoanInstallmentsSection(
                        investment: req,
                        currentUserId: auth.currentUserID,
                        onRefresh: { await loadMyRequest(for: opportunity) }
                    )
                    .padding(.horizontal, AppTheme.screenPadding)
                }

                incomeFundsTimelineSection(for: opportunity)
                    .padding(.horizontal, AppTheme.screenPadding)

                infoCard(title: "Execution plan", subtitle: "Milestones from investment acceptance", systemImage: "list.bullet.rectangle.fill") {
                    milestonesTimelineContent(for: opportunity)
                }
                .padding(.horizontal, AppTheme.screenPadding)

                if let videoRef = opportunity.effectiveVideoReference {
                    infoCard(title: "Video walkthrough", subtitle: nil, systemImage: "play.rectangle.fill") {
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

                if let sellerCard = seekerCard(for: opportunity) {
                    sellerCard
                        .padding(.horizontal, AppTheme.screenPadding)
                }

                if !opportunity.documentURLs.isEmpty {
                    infoCard(title: "Documents", subtitle: "Supporting files from the seeker", systemImage: "paperclip") {
                        documentsContent(for: opportunity)
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                }

                if !opportunity.mediaWarnings.isEmpty {
                    infoCard(title: "Upload notices", subtitle: nil, systemImage: "exclamationmark.triangle.fill") {
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

                Spacer(minLength: 4)
            }
            .padding(.bottom, 32)
        }
        .task(id: opportunity.id) {
            await loadMyRequest(for: opportunity)
            await loadSellerProfile(for: opportunity)
        }
    }

    @ViewBuilder
    private func investorEquityUpdatesContent(_ req: InvestmentListing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if req.equityUpdates.isEmpty {
                Text("No venture updates posted yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(req.equityUpdates.prefix(5)) { update in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(update.title)
                            .font(.subheadline.weight(.semibold))
                        Text(update.message)
                            .font(.footnote)
                        if let stage = update.ventureStage, !stage.isEmpty {
                            Text(stage.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }
            }
            if !req.equityMilestones.isEmpty {
                Divider()
                Text("Milestone progress")
                    .font(.subheadline.weight(.semibold))
                ForEach(req.equityMilestones) { row in
                    HStack {
                        Text(row.title)
                            .font(.footnote)
                        Spacer()
                        Text(row.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

// Card chrome

    // Single reusable card container for the detail view.
    // Pass `systemImage: nil` and `title: ""` to render a chrome-only card without a header.
    @ViewBuilder
    private func infoCard<Content: View>(
        title: String,
        subtitle: String?,
        systemImage: String?,
        trailingHeaderText: String? = nil,
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
                    if let trailingHeaderText, !trailingHeaderText.isEmpty {
                        Text(trailingHeaderText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content()
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

// Chips & small helpers

    private func chip(_ text: String, tint: Color = .secondary, filled: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(filled ? tint : .primary)
            .background(
                Group {
                    if filled {
                        Capsule().fill(tint.opacity(0.14))
                    } else {
                        Capsule().fill(AppTheme.secondaryFill)
                    }
                }
            )
    }

    private func calloutRow(title: String, value: String) -> some View {
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

// Detail sections (overview, key numbers, income & timeline)

    @ViewBuilder
    private func overviewSection(for o: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(o.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let created = o.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .omitted))
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
                    chip("Verified", tint: .blue, filled: true)
                }
                chip(o.investmentType.displayName)
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

    @ViewBuilder
    private func keyNumbersSection(for o: OpportunityListing) -> some View {
        let ticket = effectiveTicketAmount(for: o)
        let ticketText = effectiveTicketText(for: o, ticket: ticket)

        VStack(alignment: .leading, spacing: 12) {
            // Primary metrics should stand on their own (outside a "Key numbers" card).
            keyNumbersPrimaryMetric(for: o, ticket: ticket)
            Group {
                switch o.investmentType {
                case .loan:
                    loanReturnsSnapshot(for: o, ticket: ticket, ticketText: ticketText)
                case .equity:
                    infoCard(title: "Return snapshot", subtitle: nil, systemImage: nil) {
                        investorEquityValueBody(o: o, ticket: ticket, ticketText: ticketText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func loanReturnsSnapshot(for o: OpportunityListing, ticket: Double, ticketText: String) -> some View {
        let terms = effectiveLoanTerms(for: o)
        if let rate = terms.rate,
           let months = terms.months, months > 0,
           ticket > 0,
           let preview = OpportunityFinancialPreview.loanMoneyOutcome(
               principal: ticket,
               annualRatePercent: rate,
               termMonths: months,
               plan: LoanRepaymentPlan.from(terms.frequency)
           ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount to be received")
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
            investorLoanValueBody(o: o, ticket: ticket, ticketText: ticketText)
        }
    }

    @ViewBuilder
    private func keyNumbersPrimaryMetric(for o: OpportunityListing, ticket: Double) -> some View {
        switch o.investmentType {
        case .loan:
            let terms = effectiveLoanTerms(for: o)
            if let rate = terms.rate {
                if let months = terms.months, months > 0,
                   let preview = OpportunityFinancialPreview.loanMoneyOutcome(
                    principal: ticket,
                    annualRatePercent: rate,
                    termMonths: months,
                    plan: LoanRepaymentPlan.from(terms.frequency)
                   ) {
                    HStack(spacing: 8) {
                        heroLoanMetric(
                            title: "Interest rate",
                            value: "\(formatRate(rate))%",
                            tint: auth.accentColor
                        )
                        heroLoanMetric(
                            title: "Timeline",
                            value: "\(months) mo",
                            tint: .primary
                        )
                        heroLoanMetric(
                            title: "Final profit",
                            value: OpportunityFinancialPreview.formatLKRInteger(preview.interestAmount),
                            tint: .green
                        )
                    }
                } else {
                    HStack(spacing: 8) {
                        heroLoanMetric(title: "Interest rate", value: "\(formatRate(rate))%", tint: auth.accentColor)
                        heroLoanMetric(title: "Timeline", value: "—", tint: .primary)
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Rate not set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .equity:
            let eq = activeRequestForDisplay?.effectiveFinalInterestRate ?? o.terms.equityPercentage
            if let eq, eq > 0 {
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

    private func heroLoanMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        )
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

    @ViewBuilder
    private func incomeFundsTimelineSection(for o: OpportunityListing) -> some View {
        let income = o.incomeGenerationMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        infoCard(title: "Income, funds & timeline", subtitle: nil, systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 14) {
                if !income.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Income generation method")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(o.incomeGenerationMethod)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("The seeker has not added an income narrative on this listing yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !o.useOfFunds.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use of funds")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(o.useOfFunds)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            }
        }
    }

    private func canShowResolvedMilestoneCalendarDates(for o: OpportunityListing) -> Bool {
        guard let r = myLatestRequest, r.acceptedAt != nil else { return false }
        if let oid = r.opportunityId, oid != o.id { return false }
        let s = r.status.lowercased()
        if ["accepted", "active", "completed"].contains(s) { return true }
        if r.agreementStatus == .active || r.agreementStatus == .pending_signatures { return true }
        return false
    }

    @ViewBuilder
    private func milestonesTimelineContent(for o: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !o.milestones.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(o.milestones.enumerated()), id: \.offset) { index, m in
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
                                Text(m.title.isEmpty ? "Milestone" : m.title)
                                    .font(.subheadline.weight(.semibold))
                                if let due = milestoneDueDate(m, for: o) {
                                    Text(Self.mediumDate(due))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(auth.accentColor)
                                } else if let days = m.dueDaysAfterAcceptance {
                                    Text("+\(days) days from acceptance")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
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

    private func milestoneDueDate(_ milestone: OpportunityMilestone, for opportunity: OpportunityListing) -> Date? {
        if let fixed = milestone.expectedDate { return fixed }
        guard canShowResolvedMilestoneCalendarDates(for: opportunity),
              let acceptedAt = myLatestRequest?.acceptedAt,
              let days = milestone.dueDaysAfterAcceptance else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: acceptedAt)
    }

    @ViewBuilder
    private func investorLoanValueBody(o: OpportunityListing, ticket: Double, ticketText: String) -> some View {
        let terms = effectiveLoanTerms(for: o)
        if let rate = terms.rate,
           let months = terms.months, months > 0,
           ticket > 0,
           let preview = OpportunityFinancialPreview.loanMoneyOutcome(
               principal: ticket,
               annualRatePercent: rate,
               termMonths: months,
               plan: LoanRepaymentPlan.from(terms.frequency)
           ) {
            let freq = terms.frequency.displayName
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
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Modeled \(freq) cadence: first installment about \(OpportunityFinancialPreview.mediumDate(first)), last by \(OpportunityFinancialPreview.mediumDate(last)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            Text("Once this listing has a clear rate and timeline, you’ll see the projected final profit and total returned amount here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func investorEquityValueBody(o: OpportunityListing, ticket: Double, ticketText: String) -> some View {
        let t = o.terms
        if let eq = t.equityPercentage, eq > 0, o.amountRequested > 0, ticket > 0,
           let slice = OpportunityFinancialPreview.equitySlicePercent(
               roundEquityPercent: eq,
               investorAmount: ticket,
               goalAmount: o.amountRequested
           ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    compactMetric(
                        title: "Round equity",
                        value: "\(formatRate(eq))%"
                    )
                    compactMetric(
                        title: "Your est. share",
                        value: "\(formatRate(slice))%"
                    )
                    compactMetric(
                        title: "Ticket",
                        value: ticketText.replacingOccurrences(of: "LKR ", with: "")
                    )
                }
                if let v = t.businessValuation, v > 0 {
                    compactMetric(
                        title: "Valuation",
                        value: OpportunityFinancialPreview.formatLKRInteger(v)
                    )
                }
            }
        } else {
            compactMetric(title: "Ownership estimate", value: "Awaiting complete inputs")
        }
    }

    @ViewBuilder
    private func investorRevenueShareValueBody(o: OpportunityListing) -> some View {
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
    private func investorProjectValueBody(o: OpportunityListing) -> some View {
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
    private func investorCustomValueBody(o: OpportunityListing) -> some View {
        let s = (o.terms.customTermsSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty {
            Text(String(s.prefix(280)) + (s.count > 280 ? "…" : ""))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Custom summary will appear here once the seeker fills it in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

// Status card (lifted to top)

    private func shouldShowStatusCard(for opportunity: OpportunityListing) -> Bool {
        if auth.currentUserID == opportunity.ownerId { return true }
        if auth.currentUserID == nil { return false }
        if let req = myLatestRequest, req.agreementStatus == .pending_signatures {
            return false
        }
        let status = myLatestRequest?.status.lowercased() ?? ""
        if status.isEmpty && profileReadyForInvesting { return false }
        return true
    }

    @ViewBuilder
    private func statusCard(for opportunity: OpportunityListing) -> some View {
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""

        if auth.currentUserID == opportunity.ownerId {
            statusShell(tint: .secondary, icon: "person.crop.circle.fill", title: "This is your listing", message: "Switch to the Opportunity tab to manage this post.")
        } else if auth.currentUserID == nil {
            statusShell(tint: .secondary, icon: "person.crop.circle.badge.questionmark", title: "Sign in to request investment", message: "You'll need an account before sending a request.")
        } else if let r = req, status == "pending" {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader(tint: .orange, icon: "clock.fill", title: "Waiting for seeker", message: "Your request is pending. The seeker can accept or decline.")
                Button(role: .destructive) {
                    Task { await revokePendingRequest(r, opportunity: opportunity) }
                } label: {
                    if isRevokingRequest {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    } else {
                        Text("Revoke request")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRevokingRequest)

                contactSeekerCardButton(for: opportunity)
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if status == "completed" {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader(
                    tint: .green,
                    icon: "checkmark.circle.fill",
                    title: "Investment completed",
                    message: "All scheduled payments are confirmed and this deal is fully closed."
                )
                Label("Completed", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12), in: Capsule())

                contactSeekerCardButton(for: opportunity)
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if let r = req, r.agreementStatus == .active || status == "active" {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader(
                    tint: .green,
                    icon: "checkmark.seal.fill",
                    title: "Agreement active",
                    message: activeDealNextStepsMessage(for: r)
                )
                if let timeline = activeAgreementTimeline(for: r) {
                    HStack(spacing: 10) {
                        calloutRow(title: "Started", value: Self.mediumDate(timeline.start))
                        calloutRow(title: "Expected end", value: Self.mediumDate(timeline.end))
                    }
                    calloutRow(title: "Time remaining", value: timeline.daysLeft > 0 ? "\(timeline.daysLeft) days left" : "Completed")
                }
                contactSeekerCardButton(for: opportunity)
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if let r = req, r.agreementStatus == .pending_signatures {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader(tint: .blue, icon: "signature", title: "Awaiting signatures", message: r.needsInvestorSignature(currentUserId: auth.currentUserID) ? "Review and sign the agreement to continue." : "You’ve signed. Waiting for the seeker to sign.")
                if r.needsInvestorSignature(currentUserId: auth.currentUserID) {
                    Button {
                        agreementReviewContext = AgreementReviewContext(investment: r, opportunity: opportunity)
                    } label: {
                        Text("Review & sign agreement")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                } else {
                    Button {
                        agreementReviewContext = AgreementReviewContext(investment: r, opportunity: opportunity)
                    } label: {
                        Text("View agreement")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                }
                contactSeekerCardButton(for: opportunity)
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if status == "accepted" {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader(tint: .green, icon: "checkmark.circle.fill", title: "Accepted", message: "Check the Invest tab for status and use Chat to coordinate.")
                contactSeekerCardButton(for: opportunity)
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if !profileReadyForInvesting {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader(tint: .orange, icon: "person.text.rectangle", title: "Complete your profile", message: "Legal name, phone, country, city, a short bio, and experience level are required before you can send an investment request.")
                Button {
                    showProfileEdit = true
                } label: {
                    Text("Fill in profile")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.minTapTarget)
                }
                .buttonStyle(.plain)
                .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                .foregroundStyle(.white)
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if status == "declined" || status == "rejected" {
            statusShell(tint: .secondary, icon: "xmark.circle.fill", title: "Previous request declined", message: "You can send another request at any time.")
        } else {
            EmptyView()
        }
    }

    private func activeDealNextStepsMessage(for req: InvestmentListing) -> String {
        switch req.investmentType {
        case .loan:
            if req.fundingStatus == .awaiting_disbursement {
                if req.principalSentByInvestorAt == nil {
                    return "Action required: send principal to unlock repayments."
                }
                return "Principal marked sent. Waiting for seeker confirmation."
            }
            if req.fundingStatus == .disbursed {
                return "Principal confirmed. Repayments are active."
            }
            return "Loan is active."
        case .equity:
            return "The equity agreement is live. Investor funds the round, seeker executes milestones, and both parties track governance updates in chat until exit."
        }
    }

    @ViewBuilder
    private var investorPrincipalTopBanner: some View {
        switch investorPrincipalTopBannerMode {
        case .none:
            EmptyView()
        case .mustSendPrincipalAndProof:
            investorPrincipalTopBannerShell(
                icon: "arrow.up.doc.fill",
                iconTint: .orange,
                fill: Color.orange.opacity(0.12),
                stroke: Color.orange.opacity(0.25),
                title: "Send principal & transfer proof",
                message: "Transfer the loan principal to the seeker, attach screenshots or PDFs of the transfer as proof, then mark the transfer as sent. The seeker must confirm receipt before repayments begin."
            )
        case .awaitingSeekerReceiptConfirmation:
            investorPrincipalTopBannerShell(
                icon: "hourglass",
                iconTint: .blue,
                fill: Color.blue.opacity(0.12),
                stroke: Color.blue.opacity(0.25),
                title: "Awaiting seeker confirmation",
                message: "You marked the principal as sent. The seeker will confirm when the funds arrive in their account."
            )
        }
    }

    private func investorPrincipalTopBannerShell(
        icon: String,
        iconTint: Color,
        fill: Color,
        stroke: Color,
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconTint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusShell(tint: Color, icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statusHeader(tint: tint, icon: icon, title: title, message: message)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    @ViewBuilder
    private func statusHeader(tint: Color, icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func activeAgreementTimeline(for req: InvestmentListing) -> (start: Date, end: Date, daysLeft: Int)? {
        let start = req.acceptedAt ?? req.agreementGeneratedAt ?? req.createdAt
        let terms = req.agreement?.termsSnapshot
        let months: Int? = {
            switch req.investmentType {
            case .loan:
                return req.finalTimelineMonths ?? terms?.repaymentTimelineMonths
            case .equity:
                return terms?.equityTimelineMonths
            }
        }()
        guard let start, let months, months > 0 else { return nil }
        guard let end = Calendar.current.date(byAdding: .month, value: months, to: start) else { return nil }
        let rawDays = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return (start, end, max(0, rawDays))
    }

    private func dealTermsSubtitle(for o: OpportunityListing) -> String {
        switch o.investmentType {
        case .loan: return "Interest, tenor and repayment"
        case .equity: return "Equity and valuation"
        }
    }

// Terms & execution body

    @ViewBuilder
    private func termsContent(for o: OpportunityListing) -> some View {
        let t = o.terms
        let pairs = termPairs(for: o)
        VStack(alignment: .leading, spacing: 12) {
            if !pairs.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                        termChip(label: pair.label, value: pair.value)
                    }
                }
            }

            switch o.investmentType {
            case .loan:
                EmptyView()
            case .equity:
                equityTermsCards(terms: t)
            }
        }
    }

    @ViewBuilder
    private func equityTermsCards(terms t: OpportunityTerms) -> some View {
        if let ventureName = t.ventureName, !ventureName.isEmpty {
            calloutRow(title: "Venture", value: ventureName)
        }
        if let stage = t.ventureStage {
            calloutRow(title: "Stage", value: stage.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let roi = t.equityRoiTimeline {
            calloutRow(title: "ROI timeline", value: roi.displayName)
        }
        if let model = t.revenueModel, !model.isEmpty {
            calloutRow(title: "Revenue model", value: model)
        }
        if let audience = t.targetAudience, !audience.isEmpty {
            calloutRow(title: "Target market", value: audience)
        }
        if let goals = t.futureGoals, !goals.isEmpty {
            calloutRow(title: "Future goals", value: goals)
        }
        if let links = t.demoLinks, !links.isEmpty {
            calloutRow(title: "Demo links", value: links)
        }
        if let exit = t.exitPlan, !exit.isEmpty {
            calloutRow(title: "Exit plan", value: exit)
        }
    }

    private struct TermPair { let label: String; let value: String }

    private func termPairs(for o: OpportunityListing) -> [TermPair] {
        let t = o.terms
        switch o.investmentType {
        case .loan:
            let loanTerms = effectiveLoanTerms(for: o)
            var out: [TermPair] = []
            out.append(TermPair(label: "Interest", value: loanTerms.rate.map { "\(formatRate($0))%" } ?? "—"))
            out.append(TermPair(label: "Repayment", value: loanTerms.months.map { "\($0) months" } ?? o.repaymentLabel))
            out.append(TermPair(label: "Frequency", value: loanTerms.frequency.rawValue.capitalized))
            return out
        case .equity:
            var out: [TermPair] = []
            if let p = t.equityPercentage { out.append(TermPair(label: "Equity", value: String(format: "%.1f%%", p))) }
            if let v = t.businessValuation { out.append(TermPair(label: "Valuation", value: "LKR \(Int(v))")) }
            if let roi = t.equityRoiTimeline { out.append(TermPair(label: "ROI", value: roi.displayName)) }
            return out
        }
    }

    // Returns the investor's request only when the seeker has actually agreed to the proposed
    // terms. While the offer is still `pending`, the opportunity detail page must keep showing
    // the seeker's listed values (amount / rate / months) — the offer's economics only become
    // the "displayed" terms after acceptance.
    private var activeRequestForDisplay: InvestmentListing? {
        guard let req = myLatestRequest else { return nil }
        let s = req.status.lowercased()
        let acceptedStatuses: Set<String> = ["accepted", "active", "completed", "defaulted"]
        guard acceptedStatuses.contains(s) || req.acceptedAt != nil else {
            return nil
        }
        return req
    }

    private func effectiveTicketAmount(for o: OpportunityListing) -> Double {
        if let req = activeRequestForDisplay, req.effectiveAmount > 0 {
            return req.effectiveAmount
        }
        return o.minimumInvestment
    }

    private func effectiveTicketText(for o: OpportunityListing, ticket: Double) -> String {
        if activeRequestForDisplay != nil {
            return "LKR \(OpportunityFinancialPreview.formatLKRInteger(ticket)) (your request)"
        }
        return (o.maximumInvestors ?? 1) <= 1
            ? "LKR \(o.formattedAmountLKR) (full round)"
            : "LKR \(o.formattedMinimumLKR) (min. ticket)"
    }

    private func effectiveLoanTerms(for o: OpportunityListing) -> (rate: Double?, months: Int?, frequency: RepaymentFrequency) {
        if let req = activeRequestForDisplay {
            let rate = req.effectiveFinalInterestRate ?? o.terms.interestRate
            let months = req.effectiveFinalTimelineMonths ?? o.terms.repaymentTimelineMonths
            let frequency = o.terms.repaymentFrequency ?? .monthly
            return (rate, months, frequency)
        }
        return (o.terms.interestRate, o.terms.repaymentTimelineMonths, o.terms.repaymentFrequency ?? .monthly)
    }

    private func termChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func fundingStructureContent(for o: OpportunityListing) -> some View {
        let singleInvestor = (o.maximumInvestors ?? 1) <= 1
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                summaryLineItem(
                    title: "Model",
                    value: singleInvestor ? "Single investor" : "Multiple investors"
                )
                summaryLineItem(
                    title: "Funding goal",
                    value: "LKR \(o.formattedAmountLKR)"
                )
                summaryLineItem(
                    title: "Minimum ticket",
                    value: singleInvestor ? "Full amount" : "LKR \(o.formattedMinimumLKR)"
                )
                summaryLineItem(
                    title: "Capacity",
                    value: singleInvestor ? "1 investor" : "Up to \(o.maximumInvestors ?? 1)"
                )
            }

            if !singleInvestor, let cap = o.maximumInvestors, cap > 0 {
                fundingCapacityBar(filled: 0, total: cap)
            }
        }
    }

    @ViewBuilder
    private func fundingCapacityBar(filled: Int, total: Int) -> some View {
        let clampedTotal = max(total, 1)
        let clampedFilled = min(max(filled, 0), clampedTotal)
        let fraction = Double(clampedFilled) / Double(clampedTotal)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Open round")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(clampedFilled) of \(clampedTotal) investors")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.tertiaryFill)
                    Capsule()
                        .fill(auth.accentColor.opacity(0.85))
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private static func lkrText(_ value: Double) -> String {
        let n = NSNumber(value: value)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        let s = f.string(from: n) ?? String(format: "%.2f", value)
        return "LKR \(s)"
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(Int(rate))
        }
        return String(rate)
    }

    private func summaryLineItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    private func agreementAccessCard(for req: InvestmentListing, opportunity: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Agreement", systemImage: "doc.text.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(req.agreementStatus == .active ? "Active" : req.agreementStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Button {
                agreementReviewContext = AgreementReviewContext(investment: req, opportunity: opportunity)
            } label: {
                Text(req.needsInvestorSignature(currentUserId: auth.currentUserID) ? "Review & sign agreement" : "Open agreement")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(auth.accentColor)
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

// Seeker card

    @ViewBuilder
    private func seekerAvatar(profile: UserProfile, initials: String) -> some View {
        let trimmed = profile.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ZStack {
            seekerAvatarInitials(initials: initials)
            if let url = URL(string: trimmed), !trimmed.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.clear
                    }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: 44, height: 44)
        .fixedSize()
    }

    private func seekerAvatarInitials(initials: String) -> some View {
        ZStack {
            Circle()
                .fill(auth.accentColor.opacity(0.14))
            Text(initials)
                .font(.headline.weight(.bold))
                .foregroundStyle(auth.accentColor)
        }
        .frame(width: 44, height: 44)
    }

    private func seekerCard(for opportunity: OpportunityListing) -> AnyView? {
        guard auth.currentUserID != opportunity.ownerId else { return nil }
        guard let profile = sellerProfile else {
            let fallback = infoCard(title: "About the seeker", subtitle: nil, systemImage: "person.crop.square.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        seekerAvatarInitials(initials: "S")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sellerProfileLoading ? "Loading seeker details..." : "Seeker details unavailable")
                                .font(.subheadline.weight(.semibold))
                            Text("Member ID: \(shortOwnerId(opportunity.ownerId))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    if !sellerProfileLoading {
                        Text("Ask the seeker to complete their profile for richer details.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            return AnyView(fallback)
        }

        let details = profile.profileDetails
        let legal = (details?.legalFullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let display = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = !legal.isEmpty ? legal : (!display.isEmpty ? display : "Seeker")

        let cityRaw = (details?.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let countryRaw = (details?.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location: String? = {
            switch (cityRaw.isEmpty, countryRaw.isEmpty) {
            case (false, false): return "\(cityRaw), \(countryRaw)"
            case (false, true): return cityRaw
            case (true, false): return countryRaw
            default: return nil
            }
        }()

        let bio = (details?.shortBio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isVerified = (details?.verificationStatus == .verified) || (opportunity.verificationStatus == .verified)
        let experience = details?.experienceLevel?.displayName
        let initials = Self.initials(from: name)

        let hasAnyInfo = !name.isEmpty || location != nil || !bio.isEmpty || experience != nil
        guard hasAnyInfo else { return nil }

        let view = infoCard(title: "About the seeker", subtitle: nil, systemImage: "person.crop.square.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    seekerAvatar(profile: profile, initials: initials)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        if let location {
                            Text(location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if experience != nil || isVerified {
                    HStack(spacing: 8) {
                        if let experience {
                            chip(experience, tint: auth.accentColor, filled: true)
                        }
                        if isVerified {
                            chip("Verified", tint: .green, filled: true)
                        }
                    }
                }

                if !bio.isEmpty {
                    Text(bio)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        return AnyView(view)
    }

    private static func initials(from name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = parts.joined().uppercased()
        return joined.isEmpty ? "S" : joined
    }

    private func shortOwnerId(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        if trimmed.count <= 10 { return trimmed }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }

// Documents

    @ViewBuilder
    private func documentsContent(for opportunity: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(opportunity.documentURLs, id: \.self) { raw in
                if let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.richtext")
                                .font(.title3)
                                .foregroundStyle(auth.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent.isEmpty ? "Open document" : url.lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("View")
                                    .font(.caption)
                                    .foregroundStyle(auth.accentColor)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(raw)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func floatingActionBar(for opportunity: OpportunityListing) -> some View {
        // Show for any viewer who isn’t the seeker (including brief nil `currentUserID` during
        // session restore) so “Contact seeker” stays visible while a deal is in progress.
        if auth.currentUserID != opportunity.ownerId {
            VStack(spacing: 8) {
                if showsPrimaryInvestmentFloatingAction(for: opportunity) {
                    HStack(spacing: 10) {
                        Button {
                            performPrimaryFloatingAction(for: opportunity)
                        } label: {
                            Text(primaryFloatingButtonTitle(for: opportunity))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: AppTheme.minTapTarget)
                        }
                        .buttonStyle(.plain)
                        .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                        .foregroundStyle(.white)
                        .disabled(!isPrimaryFloatingActionEnabled(for: opportunity))
                        .opacity(isPrimaryFloatingActionEnabled(for: opportunity) ? 1 : 0.45)

                        if canShowOfferFloatingAction(for: opportunity) {
                            Button {
                                showOfferSheet = true
                            } label: {
                                Text("Make offer")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: AppTheme.minTapTarget)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                                    .stroke(auth.accentColor, lineWidth: 1.5)
                            )
                            .foregroundStyle(auth.accentColor)
                        }
                    }
                }

                contactSeekerFloatingButton(for: opportunity)
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func contactSeekerFloatingButton(for opportunity: OpportunityListing) -> some View {
        Button {
            Task { await openChatWithSeeker(opportunity: opportunity) }
        } label: {
            HStack(spacing: 6) {
                if isOpeningChat {
                    ProgressView()
                        .tint(auth.accentColor)
                        .controlSize(.small)
                }
                Text("Contact seeker")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.minTapTarget)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(auth.accentColor, lineWidth: 1.5)
        )
        .foregroundStyle(auth.accentColor)
        .disabled(isOpeningChat || !canContactSeeker(for: opportunity))
    }

    private func contactSeekerCardButton(for opportunity: OpportunityListing) -> some View {
        Button {
            Task { await openChatWithSeeker(opportunity: opportunity) }
        } label: {
            Label("Contact seeker", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.minTapTarget)
        }
        .buttonStyle(.bordered)
        .tint(auth.accentColor)
        .disabled(isOpeningChat || !canContactSeeker(for: opportunity))
    }

    // Hide request / “open my requests” once a deal is underway; keep signing / profile / new-request paths.
    private func showsPrimaryInvestmentFloatingAction(for listing: OpportunityListing) -> Bool {
        guard auth.currentUserID != nil, auth.currentUserID != listing.ownerId else { return false }
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""
        if let r = req, r.agreementStatus == .pending_signatures {
            return true
        }
        if status == "accepted" || status == "active" || status == "completed" {
            return false
        }
        return true
    }

    private func primaryFloatingButtonTitle(for opportunity: OpportunityListing) -> String {
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""
        if let r = req, r.agreementStatus == .pending_signatures {
            return r.needsInvestorSignature(currentUserId: auth.currentUserID) ? "Review & sign agreement" : "View agreement"
        }
        if !profileReadyForInvesting { return "Complete profile" }
        if status == "pending" { return "Request sent" }
        if status == "declined" || status == "rejected" { return "Send another request" }
        return "Request investment"
    }

    private func isPrimaryFloatingActionEnabled(for opportunity: OpportunityListing) -> Bool {
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""
        if let r = req, r.agreementStatus == .pending_signatures {
            return true
        }
        if !profileReadyForInvesting { return true }
        if status == "pending" { return false }
        return true
    }

    private func canShowOfferFloatingAction(for opportunity: OpportunityListing) -> Bool {
        guard opportunity.isNegotiable else { return false }
        guard profileReadyForInvesting else { return false }
        let status = myLatestRequest?.status.lowercased() ?? ""
        if let req = myLatestRequest, req.agreementStatus == .pending_signatures { return false }
        // Allow re-offering while a previous request/offer is still `pending`: the service
        // supersedes the old row so the seeker sees the latest negotiated terms. Without
        // this, after sending one request the investor can never update their offer.
        if status == "accepted" || status == "active" || status == "completed" {
            return false
        }
        return true
    }

    private func performPrimaryFloatingAction(for opportunity: OpportunityListing) {
        let req = myLatestRequest
        if let r = req, r.agreementStatus == .pending_signatures {
            agreementReviewContext = AgreementReviewContext(investment: r, opportunity: opportunity)
            return
        }
        if !profileReadyForInvesting {
            showProfileEdit = true
            return
        }
        showInvestSheet = true
    }

    // The sheet now performs the full submission + chat-card delivery itself, so the parent
    // only needs to refresh its local state. This avoids passing typed data across the
    // SwiftUI sheet's closure boundary, which was producing corrupted values on this build.
    private func handleProposalSubmitted(for opportunity: OpportunityListing) {
        Task {
            await loadMyRequest(for: opportunity)
            await MainActor.run {
                showRequestSuccess = true
            }
        }
    }

    private func revokePendingRequest(_ request: InvestmentListing, opportunity: OpportunityListing) async {
        guard let uid = auth.currentUserID else { return }
        isRevokingRequest = true
        defer { isRevokingRequest = false }
        do {
            try await investmentService.withdrawInvestmentRequest(investmentId: request.id, investorId: uid)
            await loadMyRequest(for: opportunity)
        } catch {
            requestActionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
            showRequestActionError = true
        }
    }

    private func loadMyRequest(for opportunity: OpportunityListing) async {
        guard let uid = auth.currentUserID, uid != opportunity.ownerId else {
            await MainActor.run { myLatestRequest = nil }
            return
        }
        do {
            let latest = try await investmentService.fetchLatestRequestForInvestor(
                opportunityId: opportunity.id,
                investorId: uid
            )
            await MainActor.run {
                myLatestRequest = latest
                if latest?.agreementStatus == .pending_signatures {
                    // Keep investor in the actionable queue while signatures are pending.
                    tabRouter.investorInvestSegment = .myRequests
                }
            }
            if !LoanRepaymentCalendarSync.hasCalendarSyncPreference,
               !showCalendarSyncPrompt,
               latest?.agreementStatus == .active {
                await MainActor.run { showCalendarSyncPrompt = true }
            }
            if let latest {
                await LoanRepaymentCalendarSync.syncPostAgreementEvents(
                    investment: latest,
                    opportunity: opportunity,
                    currentUserId: uid
                )
            }
        } catch {
            await MainActor.run { myLatestRequest = nil }
        }
    }

    private func loadUserProfile() async {
        guard let uid = auth.currentUserID else {
            await MainActor.run { userProfileLoaded = nil }
            return
        }
        do {
            let p = try await userService.fetchProfile(userID: uid)
            await MainActor.run { userProfileLoaded = p }
        } catch {
            await MainActor.run { userProfileLoaded = nil }
        }
    }

    private func loadSellerProfile(for opportunity: OpportunityListing) async {
        let ownerId = opportunity.ownerId
        guard !ownerId.isEmpty else {
            await MainActor.run {
                sellerProfile = nil
                sellerProfileLoading = false
            }
            return
        }
        await MainActor.run { sellerProfileLoading = true }
        do {
            let p = try await userService.fetchProfileResolvingLegacyIDs(userID: ownerId)
            await MainActor.run {
                sellerProfile = p
                sellerProfileLoading = false
            }
        } catch {
            await MainActor.run {
                sellerProfile = nil
                sellerProfileLoading = false
            }
        }
    }

    private func loadOpportunityFromServer() async {
        let alreadyHaveData = opportunity != nil
        if !alreadyHaveData { loadError = nil }
        let idToLoad = opportunityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idToLoad.isEmpty else {
            if !alreadyHaveData {
                await MainActor.run { loadError = "Empty opportunity ID." }
            }
            return
        }
        do {
            if let fresh = try await opportunityService.fetchOpportunity(opportunityId: idToLoad) {
                await MainActor.run {
                    opportunity = fresh
                    loadError = nil
                }
                await loadMyRequest(for: fresh)
                await loadUserProfile()
                await loadSellerProfile(for: fresh)
            } else if !alreadyHaveData {
                await MainActor.run {
                    loadError = "This listing may have been removed."
                }
            } else if let existing = opportunity {
                await loadMyRequest(for: existing)
                await loadUserProfile()
                await loadSellerProfile(for: existing)
            }
        } catch {
            if !alreadyHaveData {
                let ns = error as NSError
                await MainActor.run {
                    loadError = "\(ns.localizedDescription) [code \(ns.code)]"
                }
            } else if let existing = opportunity {
                await loadMyRequest(for: existing)
                await loadUserProfile()
                await loadSellerProfile(for: existing)
            }
        }
    }

    private func canContactSeeker(for opportunity: OpportunityListing) -> Bool {
        guard let uid = auth.currentUserID else { return false }
        return uid != opportunity.ownerId
    }

    private func openChatWithSeeker(opportunity: OpportunityListing) async {
        guard let investorId = auth.currentUserID else {
            contactError = "Sign in to message the seeker."
            showContactError = true
            return
        }
        guard investorId != opportunity.ownerId else { return }

        isOpeningChat = true
        defer { isOpeningChat = false }

        do {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opportunity.id,
                seekerId: opportunity.ownerId,
                investorId: investorId,
                opportunityTitle: opportunity.title
            )
            await MainActor.run {
                tabRouter.pendingChatDeepLink = ChatDeepLink(
                    chatId: chatId,
                    inquirySnapshot: inquirySnapshot(for: opportunity)
                )
                tabRouter.selectedTab = .chat
            }
        } catch {
            contactError = error.localizedDescription
            showContactError = true
        }
    }

    private func inquirySnapshot(for opportunity: OpportunityListing) -> OpportunityInquirySnapshot {
        OpportunityInquirySnapshot(
            opportunityId: opportunity.id,
            title: opportunity.title,
            investmentTypeLabel: opportunity.investmentType.displayName,
            fundingGoalText: "LKR \(opportunity.formattedAmountLKR)",
            minTicketText: (opportunity.maximumInvestors ?? 1) <= 1 ? "Full amount" : "LKR \(opportunity.formattedMinimumLKR)",
            termsSummary: opportunity.termsSummaryLine,
            timelineText: opportunity.repaymentLabel
        )
    }

    private func heroSection(for opportunity: OpportunityListing) -> some View {
        Group {
            if opportunity.imageStoragePaths.isEmpty {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 240)
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
    }
}

#Preview {
    NavigationStack {
        OpportunityDetailView(
            opportunity: OpportunityListing(
                id: "1",
                ownerId: "x",
                title: "Samsung phone",
                category: "Phone",
                description: "Meow",
                investmentType: .loan,
                amountRequested: 150_000,
                minimumInvestment: 150_000,
                maximumInvestors: nil,
                terms: OpportunityTerms(
                    interestRate: 11,
                    repaymentTimelineMonths: 12,
                    repaymentFrequency: .monthly
                ),
                useOfFunds: "Inventory and working capital.",
                incomeGenerationMethod: "Retail sales and repair services in Colombo.",
                milestones: [
                    OpportunityMilestone(
                        title: "Launch",
                        description: "First sales",
                        expectedDate: nil,
                        dueDaysAfterAcceptance: 30
                    )
                ],
                location: "Colombo",
                riskLevel: .medium,
                verificationStatus: .unverified,
                isNegotiable: true,
                documentURLs: [],
                status: "open",
                createdAt: Date(),
                imageStoragePaths: [],
                videoStoragePath: nil,
                videoURL: nil,
                mediaWarnings: [],
                imagePublicIds: [],
                videoPublicId: nil
            )
        )
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
    }
}
