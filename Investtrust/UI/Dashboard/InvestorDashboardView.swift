import SwiftUI

/// Investor home: portfolio tracking, not browsing (see `MarketBrowseView`).
struct InvestorDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var investments: [InvestmentListing] = []
    @State private var profile: UserProfile?
    @State private var isLoading = false
    @State private var loadError: String?

    private let investmentService = InvestmentService()
    private let userService = UserService()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerBlock

                    if profile?.profileDetails?.isCompleteForInvesting != true {
                        profileCompletionBanner
                    }

                    if isLoading && investments.isEmpty {
                        ProgressView("Loading your portfolio…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if let loadError {
                        StatusBlock(
                            icon: "exclamationmark.triangle.fill",
                            title: "Couldn't load portfolio",
                            message: loadError,
                            iconColor: .orange,
                            actionTitle: "Try again",
                            action: { Task { await load() } }
                        )
                    } else {
                        if investments.isEmpty {
                            emptyStateCard
                        } else {
                            portfolioSummarySection
                        }
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        tabRouter.selectedTab = .action
                        tabRouter.investorInvestSegment = .explore
                    } label: {
                        Label("Explore", systemImage: "safari")
                    }
                    .tint(auth.accentColor)
                }
            }
            .task(id: auth.currentUserID) {
                await load()
            }
            .refreshable { await load() }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingLine)
                .font(.title2.bold())
            Text("Investor dashboard")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var profileCompletionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Complete your profile")
                .font(.headline)
            Text("Add required profile details before sending investment requests.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                ProfileEditView()
            } label: {
                Text("Open profile form")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(auth.accentColor)
        }
        .padding(AppTheme.cardPadding)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
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

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No investments yet")
                .font(.headline)
            Text("Explore opportunities and send your first investment request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                tabRouter.selectedTab = .action
                tabRouter.investorInvestSegment = .explore
            } label: {
                    Text("Explore")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minTapTarget)
            }
            .buttonStyle(.plain)
            .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .foregroundStyle(.white)
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private var portfolioSummarySection: some View {
        let investedNow = InvestorPortfolioMetrics.totalInvestedInBook(investments)
        let expectedCurrent = InvestorPortfolioMetrics.expectedReturnCurrentInvestments(investments)
        let investedAll = InvestorPortfolioMetrics.totalInvestedAllTime(investments)
        let pureProfit = InvestorPortfolioMetrics.pureProfitAllTime(investments)
        let received = InvestorPortfolioMetrics.receivedTotal(investments)
        let recoverRate = investedAll > 0 ? min(max(received / investedAll, 0), 1) : 0
        let expectedGain = max(0, expectedCurrent - investedNow)

        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Investment overview", subtitle: "Your full money situation")

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Portfolio balance")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.84))
                        Text(signedLkr(pureProfit))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: pureProfit >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }

                HStack(spacing: 12) {
                    heroMiniPill("Current invested", lkr(investedNow))
                    heroMiniPill("Expected gain", lkr(expectedGain))
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [auth.accentColor, auth.accentColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .appCardShadow()

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                summaryTile(icon: "banknote.fill", title: "Total investments now", value: lkr(investedNow), caption: "Currently in active deals")
                summaryTile(icon: "arrow.up.forward.circle.fill", title: "Expected return (current)", value: lkr(expectedCurrent), caption: "Projected from active deals")
                summaryTile(icon: "tray.full.fill", title: "Investments made so far", value: lkr(investedAll), caption: "\(InvestorPortfolioMetrics.allTimeDealsCount(investments)) total deals")
                summaryTile(icon: "chart.line.uptrend.xyaxis.circle.fill", title: "Pure profit (all time)", value: signedLkr(pureProfit), caption: "Returned minus invested principal")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Capital recovery")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(percent(recoverRate))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(auth.accentColor)
                }
                ProgressView(value: recoverRate)
                    .tint(auth.accentColor)
                Text("How much of all-time invested capital has already been recovered.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
        }
    }

    private func summaryTile(icon: String, title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(auth.accentColor)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func heroMiniPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var upcomingSection: some View {
        let itemArray = Array(InvestorPortfolioMetrics.upcomingPayments(withinDays: 150, rows: investments).prefix(5))
        return Group {
            if !itemArray.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Upcoming payments & events", subtitle: "Projected dates")

                    VStack(spacing: 0) {
                        ForEach(Array(itemArray.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(shortDate(item.date))
                                        .font(.subheadline.weight(.semibold))
                                    Text(item.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(lkr(item.amount))
                                        .font(.subheadline.weight(.semibold))
                                    if item.isProjected {
                                        Text("Projected")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            if index < itemArray.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                    .appCardShadow()
                }
            }
        }
    }

    private var alertsSection: some View {
        let alerts = buildAlerts()
        return Group {
            if !alerts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Alerts & actions", subtitle: "Needs your attention")

                    VStack(spacing: 10) {
                        ForEach(alerts.indices, id: \.self) { i in
                            let a = alerts[i]
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: a.icon)
                                    .foregroundStyle(a.tint)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(a.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(a.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private struct DashboardAlert: Identifiable {
        let icon: String
        let title: String
        let detail: String
        let tint: Color
        var id: String { title + "|" + detail }
    }

    private func buildAlerts() -> [DashboardAlert] {
        var out: [DashboardAlert] = []
        for r in investments where r.status.lowercased() == "pending" {
            out.append(
                DashboardAlert(
                    icon: "clock.badge.questionmark",
                    title: "Waiting for seeker",
                    detail: "“\(r.opportunityTitle)” — they can accept or decline your request.",
                    tint: .orange
                )
            )
        }
        if InvestorPortfolioMetrics.receivedTotal(investments) == 0,
           InvestorPortfolioMetrics.activeDealsCount(investments) > 0 {
            out.append(
                DashboardAlert(
                    icon: "info.circle.fill",
                    title: "Repayments",
                    detail: "Received amounts appear here when recorded on your investments.",
                    tint: .blue
                )
            )
        }
        return Array(out.prefix(4))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func lkr(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let s = f.string(from: n) ?? String(format: "%.0f", v)
        return "LKR \(s)"
    }

    private func signedLkr(_ v: Double) -> String {
        let sign = v >= 0 ? "+" : "-"
        return "\(sign)\(lkr(abs(v)))"
    }

    private func percent(_ p: Double) -> String {
        "\(Int((p * 100).rounded()))%"
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func load() async {
        loadError = nil
        guard let uid = auth.currentUserID else {
            investments = []
            profile = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let invTask = investmentService.fetchInvestments(forInvestor: uid, limit: 80)
            async let profileTask = userService.fetchProfile(userID: uid)
            let (inv, prof) = try await (invTask, profileTask)
            investments = inv
            profile = prof
            HomeWidgetSnapshotWriter.persistAfterInvestorDashboardLoad(auth: auth, investments: inv)
        } catch {
            loadError = FirestoreUserFacingMessage.text(for: error)
        }
    }
}

// MARK: - Investment row card

private struct DashboardInvestmentCard: View {
    @Environment(AuthService.self) private var auth

    let investment: InvestmentListing
    var onRefresh: () async -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(investment.opportunityTitle.isEmpty ? "Investment" : investment.opportunityTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text(investment.investmentType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(auth.accentColor)
                }
                Spacer(minLength: 0)
                statusBadge(InvestorPortfolioMetrics.displayStatus(for: investment))
            }

            HStack {
                Text("Invested")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lkr(investment.investmentAmount))
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: InvestorPortfolioMetrics.progress01(for: investment))
                    .tint(auth.accentColor)
                Text(progressCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let oid = investment.opportunityId, !oid.isEmpty {
                NavigationLink {
                    OpportunityDetailView(opportunityId: oid)
                } label: {
                    Text("View opportunity")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(auth.accentColor)
            }

            if investment.isLoanWithSchedule {
                LoanInstallmentsSection(
                    investment: investment,
                    currentUserId: auth.currentUserID,
                    onRefresh: { await onRefresh() }
                )
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private var progressCaption: String {
        switch investment.investmentType {
        case .loan:
            if investment.isLoanWithSchedule {
                return "Progress (confirmed installments)"
            }
            return "Progress (time-based, projected)"
        case .revenue_share:
            return "Progress vs projected target return"
        case .project:
            return "Progress (schedule-based, projected)"
        case .equity, .custom:
            return "Deal progress (indicative)"
        }
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.secondaryFill, in: Capsule())
    }

    private func lkr(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let s = f.string(from: n) ?? String(format: "%.0f", v)
        return "LKR \(s)"
    }
}

#Preview {
    InvestorDashboardView()
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
}
