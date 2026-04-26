import SwiftUI

/// Investor-facing detail screen for a market opportunity (layout inspired by `design/invest info.svg`).
/// Always loads the listing by Firestore document ID so navigation never shows the wrong row.
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
    @State private var showProfileEdit = false

    @State private var contactError: String?
    @State private var showContactError = false
    @State private var requestActionError: String?
    @State private var showRequestActionError = false
    @State private var showRequestSuccess = false
    @State private var isOpeningChat = false
    @State private var myLatestRequest: InvestmentListing?
    @State private var showInvestSheet = false
    @State private var showOfferSheet = false
    @State private var offerOpportunityId: String = ""
    @State private var offerAmountText = ""
    @State private var offerRateText = ""
    @State private var offerTimelineText = ""
    @State private var offerDescriptionText = ""
    @State private var offerError: String?
    @State private var isSendingOffer = false
    @State private var showOfferSentAlert = false
    @State private var isRevokingRequest = false
    @State private var agreementReviewContext: AgreementReviewContext?

    private struct AgreementReviewContext: Identifiable {
        var id: String { investment.id }
        let investment: InvestmentListing
        let opportunity: OpportunityListing
    }

    /// Production path: load from Firestore by id (avoids `NavigationLink(value:)` / `Hashable` mismatches in lists).
    init(opportunityId: String) {
        self.opportunityId = opportunityId
    }

    /// Preview / tests: optional seed while network loads.
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
        .alert("Offer sent", isPresented: $showOfferSentAlert) {
            Button("OK") {}
        } message: {
            Text("Your negotiated offer was saved and posted in the chat with this seeker.")
        }
        .task(id: opportunityId) {
            await loadOpportunityFromServer()
        }
        .sheet(isPresented: $showInvestSheet) {
            if let opportunity {
                InvestProposalSheet(opportunity: opportunity) {
                    guard let uid = auth.currentUserID else {
                        throw InvestmentService.InvestmentServiceError.notSignedIn
                    }
                    let created = try await investmentService.createInvestmentRequest(
                        opportunity: opportunity,
                        investorId: uid
                    )
                    let chatId = try await chatService.getOrCreateChat(
                        opportunityId: opportunity.id,
                        seekerId: opportunity.ownerId,
                        investorId: uid,
                        opportunityTitle: opportunity.title
                    )
                    let requestSnapshot = InvestmentRequestSnapshot(
                        investmentId: created.id,
                        opportunityId: opportunity.id,
                        title: opportunity.title,
                        amountText: Self.lkrText(created.investmentAmount),
                        interestRateText: created.finalInterestRate.map { String(format: "%.2f%%", $0) } ?? "—",
                        timelineText: created.finalTimelineMonths.map { "\($0) months" } ?? "—",
                        note: "Default investment request from listing.",
                        requestKindLabel: "Investment request"
                    )
                    _ = try await chatService.sendInvestmentRequestCard(
                        chatId: chatId,
                        senderId: uid,
                        snapshot: requestSnapshot
                    )
                    await loadMyRequest(for: opportunity)
                    await MainActor.run {
                        showRequestSuccess = true
                    }
                }
            }
        }
        .sheet(isPresented: $showOfferSheet) {
            if let op = opportunity {
                NavigationStack {
                    InvestmentOfferComposerForm(
                        opportunities: [op],
                        selectedOpportunityId: $offerOpportunityId,
                        showOpportunityPicker: false,
                        emptyListingMessage: nil,
                        amountText: $offerAmountText,
                        rateText: $offerRateText,
                        timelineText: $offerTimelineText,
                        descriptionText: $offerDescriptionText,
                        errorText: offerError
                    )
                    .navigationTitle("Make offer")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showOfferSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            if isSendingOffer {
                                ProgressView()
                            } else {
                                Button("Send offer") {
                                    Task { await submitOfferFromDetail() }
                                }
                            }
                        }
                    }
                    .onAppear {
                        offerOpportunityId = op.id
                        seedOfferFieldsForOffer(from: op)
                        offerError = nil
                    }
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

    @ViewBuilder
    private func detailContent(_ opportunity: OpportunityListing) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
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

                infoCard(title: "Funding setup", subtitle: "How this round is structured", systemImage: "person.3.fill") {
                    fundingStructureContent(for: opportunity)
                }
                .padding(.horizontal, AppTheme.screenPadding)

                infoCard(title: "Deal terms", subtitle: dealTermsSubtitle(for: opportunity), systemImage: "doc.text.fill") {
                    termsContent(for: opportunity)
                }
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

    // MARK: - Card chrome

    /// Single reusable card container for the detail view.
    /// Pass `systemImage: nil` and `title: ""` to render a chrome-only card without a header.
    @ViewBuilder
    private func infoCard<Content: View>(
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

    // MARK: - Chips & small helpers

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

    // MARK: - Detail sections (overview, key numbers, income & timeline)

    @ViewBuilder
    private func overviewSection(for o: OpportunityListing) -> some View {
        infoCard(title: "Overview", subtitle: nil, systemImage: "rectangle.and.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                Text(o.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !o.category.isEmpty {
                    Text(o.category)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(o.investmentType.displayName, tint: auth.accentColor, filled: true)
                        if o.verificationStatus == .verified {
                            chip("Verified", tint: .green, filled: true)
                        }
                        let statusLower = o.status.lowercased()
                        if statusLower != "open" && !statusLower.isEmpty {
                            chip(o.status.capitalized)
                        }
                    }
                }

                if let listed = o.createdAt {
                    Text("Listed \(Self.mediumDate(listed))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if !o.description.isEmpty {
                    Text(o.description)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func keyNumbersSection(for o: OpportunityListing) -> some View {
        let ticket = o.minimumInvestment
        let ticketText = (o.maximumInvestors ?? 1) <= 1 ? "LKR \(o.formattedAmountLKR) (full round)" : "LKR \(o.formattedMinimumLKR) (min. ticket)"

        infoCard(title: "Key numbers", subtitle: "Illustrative — not financial advice", systemImage: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 14) {
                keyNumbersPrimaryMetric(for: o)
                calloutRow(title: "Required investment", value: ticketText)
                Group {
                    switch o.investmentType {
                    case .loan:
                        loanReturnsSnapshot(for: o, ticket: ticket, ticketText: ticketText)
                    case .equity:
                        investorEquityValueBody(o: o, ticket: ticket, ticketText: ticketText)
                    case .revenue_share:
                        investorRevenueShareValueBody(o: o)
                    case .project:
                        investorProjectValueBody(o: o)
                    case .custom:
                        investorCustomValueBody(o: o)
                    }
                }
                Text("Figures follow the simple-interest model used in agreements; final numbers are fixed when you invest.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Loan return snapshot")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    metricTile(title: "Interest rate", value: "\(formatRate(rate))%", tint: auth.accentColor)
                    metricTile(
                        title: "Interest amount",
                        value: "LKR \(OpportunityFinancialPreview.formatLKRInteger(preview.interestAmount))",
                        tint: auth.accentColor
                    )
                    metricTile(
                        title: "Profit",
                        value: "LKR \(OpportunityFinancialPreview.formatLKRInteger(preview.interestAmount))",
                        tint: .green
                    )
                    metricTile(
                        title: "Total back (revenue)",
                        value: "LKR \(OpportunityFinancialPreview.formatLKRInteger(preview.totalRepayable))",
                        tint: .green
                    )
                }

                Text("Based on \(ticketText) over \(months) months.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            investorLoanValueBody(o: o, ticket: ticket, ticketText: ticketText)
        }
    }

    private func metricTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func keyNumbersPrimaryMetric(for o: OpportunityListing) -> some View {
        switch o.investmentType {
        case .loan:
            if let rate = o.terms.interestRate {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(formatRate(rate))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(auth.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interest rate")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let m = o.terms.repaymentTimelineMonths {
                            Text("\(m) months · \((o.terms.repaymentFrequency ?? .monthly).displayName)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
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
        case .revenue_share:
            if let p = o.terms.revenueSharePercent, p > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(formatRate(p))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(auth.accentColor)
                    Text("Revenue share")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                placeholderPrimaryMetric(caption: "Revenue share")
            }
        case .project:
            let kind = o.terms.expectedReturnType?.rawValue.capitalized ?? "Return"
            let value = (o.terms.expectedReturnValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(auth.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                placeholderPrimaryMetric(caption: "Expected return")
            }
        case .custom:
            let s = (o.terms.customTermsSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom deal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(s.prefix(120)) + (s.count > 120 ? "…" : ""))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(auth.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                placeholderPrimaryMetric(caption: "Custom terms")
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

                calloutRow(title: "Investment timeline", value: investmentTimelineSummary(for: o))
            }
        }
    }

    private func investmentTimelineSummary(for o: OpportunityListing) -> String {
        var parts: [String] = [o.repaymentLabel]
        if o.investmentType == .loan, let f = o.terms.repaymentFrequency {
            parts.append(f.displayName)
        }
        return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "—" }.joined(separator: " · ")
    }

    private func hasLegacyMilestoneDates(_ o: OpportunityListing) -> Bool {
        o.milestones.contains { $0.dueDaysAfterAcceptance == nil && $0.expectedDate != nil }
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
        let showResolved = canShowResolvedMilestoneCalendarDates(for: o)
        let acceptedAt = myLatestRequest?.acceptedAt

        VStack(alignment: .leading, spacing: 14) {
            Text("Day 0 is when your investment is accepted on the platform.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasLegacyMilestoneDates(o) {
                Text("Some milestones use legacy calendar dates from when the listing was created.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                                if !m.description.isEmpty {
                                    Text(m.description)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let days = m.dueDaysAfterAcceptance {
                                    Text("+\(days) days from acceptance")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.green)
                                    if showResolved, let acc = acceptedAt,
                                       let due = Calendar.current.date(byAdding: .day, value: days, to: acc) {
                                        Text("On your timeline: \(Self.mediumDate(due))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if let d = m.expectedDate {
                                    Text(Self.mediumDate(d))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(auth.accentColor)
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

    @ViewBuilder
    private func investorLoanValueBody(o: OpportunityListing, ticket: Double, ticketText: String) -> some View {
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
            Text("Once this listing has a clear rate and repayment timeline, you’ll see an estimated return on the minimum ticket here.")
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
            VStack(alignment: .leading, spacing: 8) {
                Text("This round offers up to \(formatRate(eq))% equity for the full LKR \(o.formattedAmountLKR) goal.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("At \(ticketText), your pro‑rata slice is about \(formatRate(slice))% of the company if the round fills at that ticket size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let v = t.businessValuation, v > 0 {
                    Text("Seeker’s stated pre-money context: LKR \(OpportunityFinancialPreview.formatLKRInteger(v)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("Equity % and funding goal unlock a quick ownership snapshot here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Status card (lifted to top)

    private func shouldShowStatusCard(for opportunity: OpportunityListing) -> Bool {
        if auth.currentUserID == opportunity.ownerId { return true }
        if auth.currentUserID == nil { return false }
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
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if let r = req, r.agreementStatus == .active || status == "active" {
            statusShell(tint: .green, icon: "checkmark.seal.fill", title: "Agreement active", message: "The memorandum is fully signed. Use Chat to coordinate funding outside the platform.")
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
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        } else if status == "accepted" {
            statusShell(tint: .green, icon: "checkmark.circle.fill", title: "Accepted", message: "Check the Invest tab for status and use Chat to coordinate.")
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

    private func dealTermsSubtitle(for o: OpportunityListing) -> String {
        switch o.investmentType {
        case .loan: return "Interest, tenor and repayment"
        case .equity: return "Equity and valuation"
        case .revenue_share: return "Revenue share and cap"
        case .project: return "Expected return and completion"
        case .custom: return "Custom-structured deal"
        }
    }

    // MARK: - Terms & execution body

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
                if let exit = t.exitPlan, !exit.isEmpty {
                    calloutRow(title: "Exit plan", value: exit)
                }
            case .revenue_share:
                EmptyView()
            case .project:
                if let v = t.expectedReturnValue, !v.isEmpty {
                    calloutRow(title: "Expected return", value: v)
                }
            case .custom:
                if let s = t.customTermsSummary, !s.isEmpty {
                    calloutRow(title: "Summary", value: s)
                }
            }
        }
    }

    private struct TermPair { let label: String; let value: String }

    private func termPairs(for o: OpportunityListing) -> [TermPair] {
        let t = o.terms
        switch o.investmentType {
        case .loan:
            var out: [TermPair] = []
            out.append(TermPair(label: "Interest", value: "\(formatRate(t.interestRate ?? 0))%"))
            out.append(TermPair(label: "Repayment", value: t.repaymentTimelineMonths.map { "\($0) months" } ?? o.repaymentLabel))
            out.append(TermPair(label: "Frequency", value: (t.repaymentFrequency ?? .monthly).rawValue.capitalized))
            return out
        case .equity:
            var out: [TermPair] = []
            if let p = t.equityPercentage { out.append(TermPair(label: "Equity", value: String(format: "%.1f%%", p))) }
            if let v = t.businessValuation { out.append(TermPair(label: "Valuation", value: "LKR \(Int(v))")) }
            return out
        case .revenue_share:
            var out: [TermPair] = []
            if let p = t.revenueSharePercent { out.append(TermPair(label: "Rev. share", value: String(format: "%.1f%%", p))) }
            if let target = t.targetReturnAmount { out.append(TermPair(label: "Target", value: "LKR \(Int(target))")) }
            if let mx = t.maxDurationMonths { out.append(TermPair(label: "Max term", value: "\(mx) months")) }
            return out
        case .project:
            var out: [TermPair] = []
            out.append(TermPair(label: "Return type", value: t.expectedReturnType?.rawValue.capitalized ?? "—"))
            if let d = t.completionDate { out.append(TermPair(label: "Completion", value: Self.mediumDate(d))) }
            return out
        case .custom:
            return []
        }
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

    // MARK: - Seeker card

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
        guard let profile = sellerProfile else { return nil }

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

    // MARK: - Documents

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
        if auth.currentUserID != nil, auth.currentUserID != opportunity.ownerId {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
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
                }

                if canMakeNegotiatedOffer(for: opportunity) {
                    Button {
                        offerError = nil
                        seedOfferFieldsForOffer(from: opportunity)
                        offerOpportunityId = opportunity.id
                        showOfferSheet = true
                    } label: {
                        Label("Make offer", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                    .disabled(isSendingOffer)
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func canMakeNegotiatedOffer(for o: OpportunityListing) -> Bool {
        guard auth.currentUserID != nil, auth.currentUserID != o.ownerId else { return false }
        guard profileReadyForInvesting else { return false }
        guard o.isNegotiable else { return false }
        let cap = max(1, o.maximumInvestors ?? 1)
        guard cap <= 1 else { return false }
        return o.isOpenForInvesting
    }

    private func seedOfferFieldsForOffer(from op: OpportunityListing) {
        let cap = max(1, op.maximumInvestors ?? 1)
        offerAmountText = cap > 1 ? "" : String(format: "%.0f", op.amountRequested)
        offerRateText = op.interestRate > 0 ? String(format: "%.2f", op.interestRate) : ""
        offerTimelineText = "\(max(1, op.repaymentTimelineMonths))"
        offerDescriptionText = ""
    }

    private func submitOfferFromDetail() async {
        guard let uid = auth.currentUserID,
              let selected = opportunity else { return }
        let cap = max(1, selected.maximumInvestors ?? 1)
        let multi = cap > 1
        let amountValue: Double?
        if multi {
            amountValue = InvestmentOfferComposerForm.offerAmountForOpportunity(selected)
        } else {
            let cleaned = offerAmountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
            amountValue = Double(cleaned)
        }
        let rateValue = Double(offerRateText.trimmingCharacters(in: .whitespacesAndNewlines))
        let timelineDigits = offerTimelineText.filter(\.isNumber)
        let timelineValue = Int(timelineDigits)
        guard let amountValue, amountValue > 0,
              let rateValue, rateValue > 0,
              let timelineValue, timelineValue > 0 else {
            await MainActor.run {
                offerError = "Enter valid offer terms to continue."
            }
            return
        }

        isSendingOffer = true
        defer { isSendingOffer = false }
        do {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: selected.id,
                seekerId: selected.ownerId,
                investorId: uid,
                opportunityTitle: selected.title
            )
            let row = try await investmentService.createOrUpdateOfferRequest(
                opportunity: selected,
                investorId: uid,
                proposedAmount: amountValue,
                proposedInterestRate: rateValue,
                proposedTimelineMonths: timelineValue,
                description: offerDescriptionText,
                source: .detail_sheet,
                chatId: chatId
            )
            let snapshot = InvestmentOfferSnapshot(
                investmentId: row.id,
                opportunityId: selected.id,
                title: selected.title,
                amountText: InvestmentOfferComposerForm.lkr(row.offeredAmount ?? row.investmentAmount),
                interestRateText: String(format: "%.2f%%", row.offeredInterestRate ?? row.finalInterestRate ?? rateValue),
                timelineText: "\((row.offeredTimelineMonths ?? row.finalTimelineMonths ?? timelineValue)) months",
                description: offerDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                isFixedAmount: multi
            )
            _ = try await chatService.sendInvestmentOfferCard(chatId: chatId, senderId: uid, snapshot: snapshot)
            await loadMyRequest(for: selected)
            await MainActor.run {
                showOfferSheet = false
                offerDescriptionText = ""
                offerError = nil
                showOfferSentAlert = true
            }
        } catch {
            await MainActor.run {
                offerError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
            }
        }
    }

    private func primaryFloatingButtonTitle(for opportunity: OpportunityListing) -> String {
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""
        if !profileReadyForInvesting { return "Complete profile" }
        if let r = req, r.agreementStatus == .pending_signatures {
            return r.needsInvestorSignature(currentUserId: auth.currentUserID) ? "Review agreement" : "Awaiting seeker sign"
        }
        if status == "pending" { return "Request sent" }
        if status == "accepted" || status == "active" || status == "completed" { return "Open my requests" }
        if status == "declined" || status == "rejected" { return "Send another request" }
        return "Request investment"
    }

    private func isPrimaryFloatingActionEnabled(for opportunity: OpportunityListing) -> Bool {
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""
        if !profileReadyForInvesting { return true }
        if let r = req, r.agreementStatus == .pending_signatures {
            return r.needsInvestorSignature(currentUserId: auth.currentUserID)
        }
        if status == "pending" { return false }
        return true
    }

    private func performPrimaryFloatingAction(for opportunity: OpportunityListing) {
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""
        if !profileReadyForInvesting {
            showProfileEdit = true
            return
        }
        if let r = req, r.agreementStatus == .pending_signatures {
            if r.needsInvestorSignature(currentUserId: auth.currentUserID) {
                agreementReviewContext = AgreementReviewContext(investment: r, opportunity: opportunity)
            }
            return
        }
        if status == "accepted" || status == "active" || status == "completed" {
            tabRouter.selectedTab = .action
            tabRouter.investorInvestSegment = (status == "active" || status == "completed") ? .ongoing : .myRequests
            return
        }
        showInvestSheet = true
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
            await MainActor.run { myLatestRequest = latest }
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
            await MainActor.run { sellerProfile = nil }
            return
        }
        do {
            let p = try await userService.fetchProfile(userID: ownerId)
            await MainActor.run { sellerProfile = p }
        } catch {
            await MainActor.run { sellerProfile = nil }
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
