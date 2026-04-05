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
    @State private var showProfileEdit = false

    @State private var contactError: String?
    @State private var showContactError = false
    @State private var isOpeningChat = false
    @State private var myLatestRequest: InvestmentListing?
    @State private var showInvestSheet = false
    @State private var showAgreementReview = false

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
        .task(id: opportunityId) {
            await loadOpportunityFromServer()
        }
        .sheet(isPresented: $showInvestSheet) {
            if let opportunity {
                InvestProposalSheet(opportunity: opportunity) { amount in
                    guard let uid = auth.currentUserID else {
                        throw InvestmentService.InvestmentServiceError.notSignedIn
                    }
                    _ = try await investmentService.createInvestmentRequest(
                        opportunity: opportunity,
                        investorId: uid,
                        proposedAmount: amount
                    )
                    await loadMyRequest(for: opportunity)
                }
            }
        }
        .sheet(isPresented: $showAgreementReview) {
            if let opportunity, let req = myLatestRequest {
                InvestmentAgreementReviewView(
                    investment: req,
                    canSign: req.needsInvestorSignature(currentUserId: auth.currentUserID),
                    onSign: {
                        guard let uid = auth.currentUserID else {
                            throw InvestmentService.InvestmentServiceError.notSignedIn
                        }
                        try await investmentService.signAgreement(investmentId: req.id, userId: uid)
                        await loadMyRequest(for: opportunity)
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
    }

    private var profileReadyForInvesting: Bool {
        userProfileLoaded?.profileDetails?.isCompleteForInvesting == true
    }

    @ViewBuilder
    private func detailContent(_ opportunity: OpportunityListing) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heroSection(for: opportunity)
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.top, 8)

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
                            tagPill(text: opportunity.investmentType.displayName, icon: "chart.pie.fill", tint: AppTheme.accent)
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
                .padding(.horizontal, AppTheme.screenPadding)

                dealSnapshotCard(for: opportunity)
                    .padding(.horizontal, AppTheme.screenPadding)

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

                if !opportunity.description.isEmpty {
                    sectionCard(title: "The story", subtitle: "Why this exists", systemImage: "text.quote") {
                        Text(opportunity.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                }

                sectionCard(title: "The deal", subtitle: "What you’re signing up for", systemImage: "doc.text.fill") {
                    termsContent(for: opportunity)
                }
                .padding(.horizontal, AppTheme.screenPadding)

                sectionCard(title: "Execution & trust", subtitle: "Where money goes and what to expect", systemImage: "map.fill") {
                    executionContent(for: opportunity)
                }
                .padding(.horizontal, AppTheme.screenPadding)

                if !opportunity.documentURLs.isEmpty {
                    sectionCard(title: "Documents", subtitle: "Supporting files from the seeker", systemImage: "paperclip") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(opportunity.documentURLs, id: \.self) { raw in
                                if let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                                    Link(destination: url) {
                                        HStack(spacing: 10) {
                                            Image(systemName: "doc.richtext")
                                                .font(.title3)
                                                .foregroundStyle(AppTheme.accent)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(url.lastPathComponent.isEmpty ? "Open document" : url.lastPathComponent)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                Text("View")
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.accent)
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
                    .padding(.horizontal, AppTheme.screenPadding)
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
                    investActionBlock(for: opportunity)

                    Button {
                        Task { await openChatWithSeeker(opportunity: opportunity) }
                    } label: {
                        HStack {
                            if isOpeningChat {
                                ProgressView()
                                    .tint(AppTheme.accent)
                            }
                            Text("Contact seeker")
                                .font(.headline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            .stroke(AppTheme.accent, lineWidth: 1.5)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .disabled(isOpeningChat || !canContactSeeker(for: opportunity))
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .task(id: opportunity.id) {
            await loadMyRequest(for: opportunity)
        }
    }

    // MARK: - Deal snapshot (at-a-glance grid)

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
                    iconTint: AppTheme.accent
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
                        .foregroundStyle(AppTheme.accent)
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

    // MARK: - Section chrome

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
                    .foregroundStyle(AppTheme.accent)
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
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    // MARK: - Tags

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

    // MARK: - Terms & execution body

    @ViewBuilder
    private func termsContent(for o: OpportunityListing) -> some View {
        let t = o.terms
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                switch o.investmentType {
                case .loan:
                    termChip(label: "Interest", value: "\(formatRate(t.interestRate ?? 0))%")
                    termChip(label: "Repayment", value: "\(t.repaymentTimelineMonths.map { "\($0) mo" } ?? o.repaymentLabel)")
                    termChip(label: "Frequency", value: (t.repaymentFrequency ?? .monthly).rawValue.capitalized)
                case .equity:
                    if let p = t.equityPercentage {
                        termChip(label: "Equity", value: String(format: "%.1f%%", p))
                    }
                    if let v = t.businessValuation {
                        termChip(label: "Valuation", value: "LKR \(Int(v))")
                    }
                case .revenue_share:
                    if let p = t.revenueSharePercent {
                        termChip(label: "Rev. share", value: String(format: "%.1f%%", p))
                    }
                    if let target = t.targetReturnAmount {
                        termChip(label: "Target", value: "LKR \(Int(target))")
                    }
                    if let mx = t.maxDurationMonths {
                        termChip(label: "Max term", value: "\(mx) mo")
                    }
                case .project:
                    termChip(label: "Return type", value: t.expectedReturnType?.rawValue.capitalized ?? "—")
                    if let d = t.completionDate {
                        termChip(label: "Completion", value: Self.mediumDate(d))
                    }
                case .custom:
                    EmptyView()
                }
            }

            switch o.investmentType {
            case .loan:
                EmptyView()
            case .equity:
                if let exit = t.exitPlan, !exit.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Exit plan")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(exit)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }
            case .revenue_share:
                EmptyView()
            case .project:
                if let v = t.expectedReturnValue, !v.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Expected return")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(v)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }
            case .custom:
                if let s = t.customTermsSummary, !s.isEmpty {
                    Text(s)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func executionContent(for o: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !o.useOfFunds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Use of funds", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(o.useOfFunds)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !o.milestones.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Milestones")
                        .font(.subheadline.weight(.semibold))

                    ForEach(Array(o.milestones.enumerated()), id: \.offset) { index, m in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 10, height: 10)
                                if index < o.milestones.count - 1 {
                                    Rectangle()
                                        .fill(AppTheme.accent.opacity(0.35))
                                        .frame(width: 2, height: 36)
                                }
                            }
                            .frame(width: 14)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.title.isEmpty ? "Milestone" : m.title)
                                    .font(.subheadline.weight(.semibold))
                                if !m.description.isEmpty {
                                    Text(m.description)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let d = m.expectedDate {
                                    Text(Self.mediumDate(d))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .padding(.bottom, index < o.milestones.count - 1 ? 4 : 0)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(o.location.isEmpty ? "Not specified" : o.location)
                            .font(.body.weight(.medium))
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Risk")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(o.riskLevel.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(riskAccent(o.riskLevel))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verification")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(o.verificationStatus.rawValue.capitalized)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(12)
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        }
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(Int(rate))
        }
        return String(rate)
    }

    @ViewBuilder
    private func investActionBlock(for opportunity: OpportunityListing) -> some View {
        let req = myLatestRequest
        let status = req?.status.lowercased() ?? ""

        if auth.currentUserID == opportunity.ownerId {
            Text("This is your listing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if auth.currentUserID == nil {
            Text("Sign in to send an investment request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if status == "pending" {
            VStack(alignment: .leading, spacing: 6) {
                Text("Waiting for seeker")
                    .font(.headline.weight(.semibold))
                Text("Your request is pending. The seeker can accept or decline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else if let r = req, r.agreementStatus == .active || status == "active" {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agreement active")
                    .font(.headline.weight(.semibold))
                Text("The memorandum is fully signed. Use Chat to coordinate funding outside the platform.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else if let r = req, r.agreementStatus == .pending_signatures {
            VStack(alignment: .leading, spacing: 12) {
                Text("Awaiting signatures")
                    .font(.headline.weight(.semibold))
                if r.needsInvestorSignature(currentUserId: auth.currentUserID) {
                    Text("Review and sign the memorandum of agreement to continue.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showAgreementReview = true
                    } label: {
                        Text("Review & sign agreement")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                } else {
                    Text("You’ve signed. Waiting for the seeker to sign the agreement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showAgreementReview = true
                    } label: {
                        Text("View agreement")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else if status == "accepted" {
            VStack(alignment: .leading, spacing: 6) {
                Text("Accepted")
                    .font(.headline.weight(.semibold))
                Text("Check the Invest tab for status and use Chat to coordinate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else if !profileReadyForInvesting {
            VStack(alignment: .leading, spacing: 12) {
                Text("Complete your profile")
                    .font(.headline.weight(.semibold))
                Text("Legal name, phone, country, city, a short bio, and experience level are required before you can send an investment request.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showProfileEdit = true
                } label: {
                    Text("Fill in profile")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        } else {
            Button {
                showInvestSheet = true
            } label: {
                Text(status == "declined" || status == "rejected" ? "Send another request" : "Invest")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .foregroundStyle(.white)
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

    private func loadOpportunityFromServer() async {
        loadError = nil
        do {
            guard let fresh = try await opportunityService.fetchOpportunity(opportunityId: opportunityId) else {
                await MainActor.run {
                    loadError = "This listing may have been removed."
                    opportunity = nil
                }
                return
            }
            await MainActor.run {
                opportunity = fresh
            }
            await loadMyRequest(for: fresh)
            await loadUserProfile()
        } catch {
            await MainActor.run {
                loadError = (error as NSError).localizedDescription
                opportunity = nil
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
                tabRouter.pendingChatDeepLink = ChatDeepLink(chatId: chatId)
                tabRouter.selectedTab = .chat
            }
        } catch {
            contactError = error.localizedDescription
            showContactError = true
        }
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
                minimumInvestment: 10_000,
                maximumInvestors: nil,
                terms: OpportunityTerms(
                    interestRate: 11,
                    repaymentTimelineMonths: 12,
                    repaymentFrequency: .monthly
                ),
                useOfFunds: "Inventory and working capital.",
                milestones: [
                    OpportunityMilestone(title: "Launch", description: "First sales", expectedDate: Date())
                ],
                location: "Colombo",
                riskLevel: .medium,
                verificationStatus: .unverified,
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
