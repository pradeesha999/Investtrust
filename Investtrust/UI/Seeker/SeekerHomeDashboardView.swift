//
//  SeekerHomeDashboardView.swift
//  Investtrust
//
//  Seeker **Home** tab: capital overview, investor activity, and listings.
//

import SwiftUI

struct SeekerHomeDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var myOpportunities: [OpportunityListing] = []
    @State private var seekerInvestments: [InvestmentListing] = []
    @State private var profile: UserProfile?
    @State private var isLoading = false
    @State private var loadError: String?

    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()
    private let userService = UserService()

    private var sortedInvestments: [InvestmentListing] {
        seekerInvestments.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private func isDeclinedLike(_ inv: InvestmentListing) -> Bool {
        let s = inv.status.lowercased()
        return InvestmentListing.nonBlockingStatusesForSeeker.contains(s)
    }

    private var openListingsCount: Int {
        myOpportunities.filter { $0.status.lowercased() == "open" }.count
    }

    private var pendingReviewCount: Int {
        seekerInvestments.filter { $0.status.lowercased() == "pending" }.count
    }

    private var liveDealsCount: Int {
        seekerInvestments.filter {
            $0.agreementStatus == .active || $0.status.lowercased() == "active"
        }.count
    }

    private var awaitingSignaturesCount: Int {
        seekerInvestments.filter { $0.agreementStatus == .pending_signatures }.count
    }

    private var completedDealsCount: Int {
        seekerInvestments.filter { $0.status.lowercased() == "completed" }.count
    }

    private var principalConfirmationNeededCount: Int {
        seekerInvestments.filter {
            $0.investmentType == .loan
                && $0.agreementStatus == .active
                && $0.fundingStatus == .awaiting_disbursement
        }.count
    }

    private func pendingCount(for opportunityId: String) -> Int {
        seekerInvestments.filter {
            $0.opportunityId == opportunityId && $0.status.lowercased() == "pending"
        }.count
    }

    private func opportunityMatch(for inv: InvestmentListing) -> OpportunityListing? {
        guard let oid = inv.opportunityId else { return nil }
        return myOpportunities.first { $0.id == oid }
    }

    private func committedPrincipal(for opportunityId: String) -> Double {
        seekerInvestments
            .filter { $0.opportunityId == opportunityId && !isDeclinedLike($0) }
            .reduce(0) { $0 + $1.investmentAmount }
    }

    private var opportunitiesNeedingAttention: [OpportunityListing] {
        myOpportunities
            .filter { pendingCount(for: $0.id) > 0 }
            .sorted { pendingCount(for: $0.id) > pendingCount(for: $1.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                    greetingHeader

                    if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(AppTheme.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                            .appCardShadow()
                    } else if isLoading && myOpportunities.isEmpty && seekerInvestments.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else if myOpportunities.isEmpty && seekerInvestments.isEmpty {
                        emptyStateCreateCard
                    } else {
                        pipelineOverviewCard

                        if !homeInsightLines.isEmpty {
                            insightsCard
                        }

                        if !opportunitiesNeedingAttention.isEmpty {
                            attentionSection
                        }

                        investorActivitySection

                        Text("Your listings")
                            .font(.title3.weight(.bold))
                            .padding(.top, 4)

                        if myOpportunities.isEmpty {
                            Text("No listings yet — open the Create tab to add one.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(AppTheme.cardPadding)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(myOpportunities) { item in
                                    NavigationLink {
                                        SeekerOpportunityDetailView(
                                            opportunity: item,
                                            onMutate: { Task { await loadHomeData() } },
                                            onAcceptedRequest: { Task { await loadHomeData() } }
                                        )
                                    } label: {
                                        homeListingRow(item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(AppTheme.screenPadding)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .task { await loadHomeData() }
            .refreshable { await loadHomeData() }
        }
    }

    // MARK: - Overview

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingLine)
                .font(.title2.bold())
            Text("See your pipeline, investor activity, and listings in one place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingLine: String {
        let name = greetingName
        return name.isEmpty ? "Welcome" : "Hi, \(name)"
    }

    private var greetingName: String {
        if let n = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        if let e = auth.currentUserEmail, let at = e.firstIndex(of: "@") {
            let local = e[..<at]
            return local.capitalized
        }
        return ""
    }

    private var pipelineOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pipeline overview")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Track listing momentum and deal progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                metricTile(
                    value: "\(openListingsCount)",
                    label: "Open listings",
                    icon: "leaf.fill",
                    tint: .green
                )
                metricTile(
                    value: "\(pendingReviewCount)",
                    label: "Pending requests",
                    icon: "tray.full.fill",
                    tint: .orange
                )
                metricTile(
                    value: "\(awaitingSignaturesCount)",
                    label: "Awaiting signatures",
                    icon: "signature",
                    tint: .blue
                )
            }

            HStack(spacing: 10) {
                metricTile(
                    value: "\(liveDealsCount)",
                    label: "Active agreements",
                    icon: "checkmark.shield.fill",
                    tint: .green
                )
                metricTile(
                    value: "\(principalConfirmationNeededCount)",
                    label: "Need principal confirm",
                    icon: "banknote.fill",
                    tint: .orange
                )
                metricTile(
                    value: "\(completedDealsCount)",
                    label: "Completed deals",
                    icon: "flag.checkered",
                    tint: auth.accentColor
                )
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [auth.accentColor.opacity(0.12), AppTheme.cardBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .appCardShadow()
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Insights", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(auth.accentColor)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(homeInsightLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private var emptyStateCreateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No opportunities yet")
                .font(.title3.weight(.bold))
            Text("Create your first opportunity to start receiving investor requests.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                tabRouter.selectedTab = .action
                tabRouter.openSeekerCreateWizard = true
            } label: {
                Text("Create opportunity")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minTapTarget)
            }
            .buttonStyle(.plain)
            .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .foregroundStyle(.white)
            .padding(.top, 4)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 280, alignment: .center)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func metricTile(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
    }

    private var homeInsightLines: [String] {
        var lines: [String] = []
        if openListingsCount == 0, !myOpportunities.isEmpty {
            lines.append("All your listings are currently closed. Open a new listing to attract fresh requests.")
        }
        if pendingReviewCount > 0 {
            lines.append("You have \(pendingReviewCount) pending \(pendingReviewCount == 1 ? "request" : "requests") waiting for your response.")
        }
        if awaitingSignaturesCount > 0 {
            lines.append("\(awaitingSignaturesCount) \(awaitingSignaturesCount == 1 ? "deal is" : "deals are") waiting on signatures to go live.")
        }
        if principalConfirmationNeededCount > 0 {
            lines.append("\(principalConfirmationNeededCount) loan \(principalConfirmationNeededCount == 1 ? "deal needs" : "deals need") principal confirmation before repayments start.")
        }
        if lines.isEmpty, liveDealsCount > 0 {
            lines.append("Your active agreements are healthy. Keep tracking milestones and investor communication.")
        }
        return Array(lines.prefix(3))
    }

    // MARK: - Investor activity

    private var investorActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Investor activity")
                    .font(.title3.weight(.bold))
                Spacer(minLength: 8)
                Text("\(sortedInvestments.count) \(sortedInvestments.count == 1 ? "record" : "records")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Every request and deal with amounts and current status.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if sortedInvestments.isEmpty {
                Text("Investor requests and deal progress will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(AppTheme.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                    .appCardShadow()
            } else {
                VStack(spacing: 10) {
                    ForEach(sortedInvestments) { inv in
                        investmentDealRow(inv)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func investmentDealRow(_ inv: InvestmentListing) -> some View {
        let opp = opportunityMatch(for: inv)
        let label = investmentDealRowLabel(inv)
        if let opp {
            NavigationLink {
                SeekerOpportunityDetailView(
                    opportunity: opp,
                    onMutate: { Task { await loadHomeData() } },
                    onAcceptedRequest: { Task { await loadHomeData() } }
                )
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func investmentDealRowLabel(_ inv: InvestmentListing) -> some View {
        let opp = opportunityMatch(for: inv)
        return HStack(alignment: .top, spacing: 12) {
            investmentThumb(opp)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inv.opportunityTitle.isEmpty ? "Opportunity" : inv.opportunityTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if isDeclinedLike(inv) {
                            Text("Closed — no longer active")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(formatLKR(inv.investmentAmount))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(auth.accentColor)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 8) {
                    Text(inv.lifecycleDisplayTitle)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(investmentStatusTint(inv).opacity(0.15), in: Capsule())
                        .foregroundStyle(investmentStatusTint(inv))

                    Text("Deal · \(shortId(inv.id))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if inv.isLoanWithSchedule, inv.agreementStatus == .active {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Repayments logged: \(formatLKR(inv.receivedAmount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if opportunityMatch(for: inv) != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
        )
        .appCardShadow()
    }

    @ViewBuilder
    private func investmentThumb(_ opp: OpportunityListing?) -> some View {
        let corner = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if let first = opp?.imageStoragePaths.first {
            StorageBackedAsyncImage(
                reference: first,
                height: 56,
                cornerRadius: 10,
                feedThumbnail: true
            )
            .frame(width: 56, height: 56)
            .clipShape(corner)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.secondaryFill)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func investmentStatusTint(_ inv: InvestmentListing) -> Color {
        if isDeclinedLike(inv) { return .secondary }
        switch inv.agreementStatus {
        case .active:
            return .green
        case .pending_signatures:
            return .orange
        case .none:
            break
        }
        switch inv.status.lowercased() {
        case "pending":
            return .orange
        case "accepted":
            return .blue
        case "active":
            return .green
        case "completed":
            return .secondary
        default:
            return .primary
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                Text("Needs your attention")
                    .font(.title3.weight(.bold))
                Spacer(minLength: 0)
            }
            Text("Investors are waiting for you to accept or decline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(opportunitiesNeedingAttention) { opp in
                    let n = pendingCount(for: opp.id)
                    NavigationLink {
                        SeekerOpportunityDetailView(
                            opportunity: opp,
                            onMutate: { Task { await loadHomeData() } },
                            onAcceptedRequest: { Task { await loadHomeData() } }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.18))
                                    .frame(width: 44, height: 44)
                                Text("\(n)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(opp.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(n == 1 ? "1 pending request" : "\(n) pending requests")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(AppTheme.cardPadding)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                        )
                        .appCardShadow()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadHomeData() async {
        guard let userID = auth.currentUserID else { return }
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            async let opps = opportunityService.fetchSeekerListings(ownerId: userID)
            async let invs = investmentService.fetchInvestmentsForSeeker(seekerId: userID)
            async let p = userService.fetchProfile(userID: userID)
            myOpportunities = try await opps
            seekerInvestments = try await invs
            profile = try await p
            HomeWidgetSnapshotWriter.persistAfterSeekerHomeLoad(auth: auth, seekerInvestments: seekerInvestments)
        } catch {
            profile = nil
            loadError = FirestoreUserFacingMessage.text(for: error)
        }
    }

    private func homeListingRow(_ item: OpportunityListing) -> some View {
        let pending = pendingCount(for: item.id)
        let live = seekerInvestments.contains {
            $0.opportunityId == item.id && ($0.agreementStatus == .active || $0.status.lowercased() == "active")
        }
        let committed = committedPrincipal(for: item.id)

        return VStack(alignment: .leading, spacing: 12) {
            homeRowMedia(item)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    homeStatusChip(item.status)
                    if pending > 0 {
                        Text("\(pending) pending")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    } else if live {
                        Text("Active deal")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Funding goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("LKR \(item.formattedAmountLKR)")
                        .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Investor interest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(committed > 0 ? formatLKR(committed) : "—")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(committed > 0 ? auth.accentColor : .secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.investmentType.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }

            if !item.termsSummaryLine.isEmpty {
                Text(item.termsSummaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            HStack {
                Text("Manage listing")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(auth.accentColor)
            .padding(.top, 4)
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func homeStatusChip(_ status: String) -> some View {
        let s = status.lowercased()
        let (fg, bg): (Color, Color) = {
            switch s {
            case "open": return (.green, Color.green.opacity(0.15))
            case "closed", "filled", "funded": return (.secondary, AppTheme.secondaryFill)
            default: return (.primary, AppTheme.secondaryFill)
            }
        }()
        return Text(status.capitalized)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
    }

    @ViewBuilder
    private func homeRowMedia(_ item: OpportunityListing) -> some View {
        if let first = item.imageStoragePaths.first {
            StorageBackedAsyncImage(
                reference: first,
                height: 180,
                cornerRadius: 16,
                feedThumbnail: true
            )
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray5))
                .frame(height: 180)
                .overlay {
                    Image(systemName: item.effectiveVideoReference != nil ? "play.rectangle.fill" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func formatLKR(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let s = f.string(from: n) ?? String(format: "%.0f", v)
        return "LKR \(s)"
    }

    private func shortId(_ id: String) -> String {
        guard id.count > 10 else { return id }
        return "\(id.prefix(6))…\(id.suffix(4))"
    }
}

#Preview {
    SeekerHomeDashboardView()
        .environment(AuthService.previewSignedIn)
}
