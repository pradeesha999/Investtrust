import SwiftUI

// Investor Home tab — shows KPI cards (total invested, profit/loss), earnings chart,
// upcoming payments list, and active deal cards for quick access
private enum InvestorEarningsPeriod: String, CaseIterable {
    case annual
    case quarterly
    case monthly

    var title: String {
        switch self {
        case .annual: return "Annual"
        case .quarterly: return "Quarterly"
        case .monthly: return "Monthly"
        }
    }
}

private struct InvestorChartBucket: Identifiable {
    let id: String
    let axisLabel: String
    let principal: Double
    let interest: Double
    var total: Double { principal + interest }
}

private struct TopRecipient: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String?
    let activeSince: Date
    let dealCount: Int
    let totalAmount: Double
}

// Investor home: portfolio tracking, not browsing (see `MarketBrowseView`).
struct InvestorDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var investments: [InvestmentListing] = []
    @State private var profile: UserProfile?
    @State private var seekerProfiles: [String: UserProfile] = [:]
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var earningsPeriod: InvestorEarningsPeriod = .annual
    @State private var hasInitializedYearSelection = false
    @State private var selectedDashboardYear: Int = Calendar.current.component(.year, from: Date())

    private let investmentService = InvestmentService()
    private let userService = UserService()

    private let dashboardPink = Color(red: 1.0, green: 45.0 / 255.0, blue: 85.0 / 255.0)
    private let dashboardLightPink = Color(red: 1.0, green: 200.0 / 255.0, blue: 211.0 / 255.0)
    private let dashboardCardFill = Color(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0)
    private let dashboardTrackFill = Color(red: 229.0 / 255.0, green: 229.0 / 255.0, blue: 234.0 / 255.0)
    private let dashboardGray = Color(red: 217.0 / 255.0, green: 217.0 / 255.0, blue: 217.0 / 255.0)
    private let dashboardOutline = Color(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 147.0 / 255.0)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    dashboardHeader
                    heroProfitsGainedBlock
                    earningsPeriodSelector
                    earningsStatGrid
                    activitySection
                    nextPaymentCard

                    if let loadError {
                        StatusBlock(
                            icon: "exclamationmark.triangle.fill",
                            title: "Couldn't load portfolio",
                            message: loadError,
                            iconColor: .orange,
                            actionTitle: "Try again",
                            action: { Task { await load() } }
                        )
                    } else if isLoading && investments.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if investments.isEmpty {
                        emptyExploreCard
                    } else {
                        topRecipientsSection
                        ongoingListingsSection
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: auth.currentUserID) {
                await load()
            }
            .refreshable { await load() }
            .onAppear {
                guard !hasInitializedYearSelection else { return }
                selectedDashboardYear = currentYear
                hasInitializedYearSelection = true
            }
        }
    }

// Header

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Dashboard")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
            Menu {
                ForEach(yearOptions, id: \.self) { y in
                    Button(String(y)) {
                        selectedDashboardYear = y
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(selectedDashboardYear))
                        .font(.system(size: 14, weight: .regular))
                }
                .foregroundStyle(dashboardOutline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(dashboardOutline, lineWidth: 1)
                )
            }
            Spacer(minLength: 0)
        }
    }

// Hero summary (profits)

    // Net profit across the portfolio: all cash received minus all principal ever deployed (excludes pending requests).
    private var profitsGainedAllTime: Double {
        InvestorPortfolioMetrics.pureProfitAllTime(investments)
    }

    private var heroProfitsGainedBlock: some View {
        let p = profitsGainedAllTime
        return VStack(alignment: .leading, spacing: 6) {
            Text("PROFITS GAINED")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .tracking(0.5)

            Text("Rs. \(formatAmount(p))")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(p >= 0 ? Color.green : dashboardPink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("All time. Net of repayments and returns vs principal you put in.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

// Period selector

    private var earningsPeriodSelector: some View {
        HStack(spacing: 4) {
            ForEach(InvestorEarningsPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        earningsPeriod = period
                    }
                } label: {
                    Text(period.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(earningsPeriod == period ? .white : .black)
                        .frame(minWidth: 78)
                        .frame(height: 30)
                        .background(
                            Group {
                                if earningsPeriod == period {
                                    Capsule().fill(dashboardPink)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(dashboardTrackFill, in: Capsule())
        .frame(height: 36)
        .frame(maxWidth: 248, alignment: .leading)
    }

// Stat grid

    private var earningsStatGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            statCard(title: "TOTAL INVESTED", value: "Rs. \(formatAmount(totalInvestedAllTime))", valueColor: .black)
            statCard(title: "RETURNS", value: "Rs. \(formatAmount(totalReturnsReceived))", valueColor: dashboardPink)
            statCard(
                title: "TOTAL LIABILITY",
                value: "Rs. \(formatAmount(totalLiability))",
                valueColor: .red,
                subtitle: liabilityStatPeriodSubtitle
            )
            statCard(
                title: "PENDING REQUESTS",
                value: "\(pendingRequestsCount)",
                valueColor: dashboardPink,
                subtitle: "Active deals: \(activeInvestmentsCount)"
            )
        }
    }

    private func statCard(title: String, value: String, valueColor: Color, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .tracking(0.4)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

// Activity chart

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Activity")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)

            HStack(spacing: 18) {
                legendItem(color: dashboardGray, label: "VALUE")
                legendItem(color: dashboardLightPink, label: "INTEREST")
                Spacer(minLength: 0)
            }

            activityChart
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
    }

    private var activityChart: some View {
        let yLabels = chartYTickValues
        let yMax = chartYMax
        let activities = chartBuckets
        let chartHeight: CGFloat = 220
        let yLabelWidth: CGFloat = 40
        let barW = chartBarWidth
        let barGap = chartBarSpacing

        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(yLabels, id: \.self) { v in
                        Text(formatThousandsK(v))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: yLabelWidth, height: chartHeight)

                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        ForEach(yLabels.indices, id: \.self) { _ in
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color(red: 235 / 255.0, green: 235 / 255.0, blue: 235 / 255.0))
                                    .frame(height: 1)
                            }
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .frame(height: chartHeight)

                    Group {
                        if usesDistributedXAxis {
                            HStack(alignment: .bottom, spacing: 0) {
                                ForEach(activities) { item in
                                    stackedBar(for: item, yMax: yMax, totalHeight: chartHeight, barWidth: barW)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        } else {
                            HStack(alignment: .bottom, spacing: barGap) {
                                ForEach(activities) { item in
                                    stackedBar(for: item, yMax: yMax, totalHeight: chartHeight, barWidth: barW)
                                }
                            }
                        }
                    }
                    .frame(height: chartHeight, alignment: .bottom)
                    .padding(.horizontal, 4)
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: yLabelWidth)
                Group {
                    if usesDistributedXAxis {
                        HStack(spacing: 0) {
                            ForEach(activities) { item in
                                Text(item.axisLabel)
                                    .font(chartAxisLabelFont)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                    } else {
                        HStack(spacing: barGap) {
                            ForEach(activities) { item in
                                Text(item.axisLabel)
                                    .font(chartAxisLabelFont)
                                    .foregroundStyle(.secondary)
                                    .frame(width: chartAxisLabelWidth)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: earningsPeriod)
        .animation(.easeInOut(duration: 0.22), value: selectedDashboardYear)
    }

    private func stackedBar(for item: InvestorChartBucket, yMax: Double, totalHeight: CGFloat, barWidth: CGFloat) -> some View {
        let principalHeight = CGFloat(min(item.principal / yMax, 1.0)) * totalHeight
        let interestHeight = CGFloat(min(item.interest / yMax, 1.0)) * totalHeight
        let combined = max(0, totalHeight - (principalHeight + interestHeight))

        return VStack(spacing: 0) {
            Spacer().frame(height: combined)
            Rectangle()
                .fill(dashboardLightPink)
                .frame(width: barWidth, height: max(0, interestHeight))
            Rectangle()
                .fill(dashboardGray)
                .frame(width: barWidth, height: max(0, principalHeight))
        }
        .frame(width: barWidth, height: totalHeight, alignment: .bottom)
    }

    private var nextPaymentInfo: (title: String, amount: Double, days: Int)? {
        let today = Calendar.current.startOfDay(for: Date())
        let upcoming = InvestorPortfolioMetrics
            .upcomingPayments(withinDays: 3650, rows: timelineScopedInvestments.filter { InvestorPortfolioMetrics.isOngoingDeal($0) })
            .first(where: { Calendar.current.startOfDay(for: $0.date) >= today })
        guard let upcoming else { return nil }
        let days = max(0, Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: upcoming.date)).day ?? 0)
        return (upcoming.title, upcoming.amount, days)
    }

    private var nextPaymentCard: some View {
        Group {
            if let next = nextPaymentInfo {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(dashboardPink)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next payment in \(next.days) day\(next.days == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(next.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("Rs. \(formatAmount(next.amount))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(dashboardPink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

// Top recipients

    @ViewBuilder
    private var topRecipientsSection: some View {
        if !topRecipients.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Recipients")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)

                VStack(spacing: 10) {
                    ForEach(topRecipients) { recipient in
                        topRecipientRow(recipient)
                    }
                }
            }
        }
    }

    private func topRecipientRow(_ recipient: TopRecipient) -> some View {
        HStack(spacing: 12) {
            recipientAvatar(recipient)
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(recipient.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Text("Active since \(monthYearLabel(recipient.activeSince))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(formatBadge(recipient.totalAmount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(dashboardOutline.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func recipientAvatar(_ recipient: TopRecipient) -> some View {
        if let url = recipient.avatarURL, !url.isEmpty {
            StorageBackedAsyncImage(
                reference: url,
                height: 44,
                cornerRadius: 22,
                feedThumbnail: true
            )
            .frame(width: 44, height: 44)
        } else {
            ZStack {
                Circle()
                    .fill(dashboardPink.opacity(0.15))
                Text(initials(for: recipient.displayName))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(dashboardPink)
            }
        }
    }

// Ongoing listings

    @ViewBuilder
    private var ongoingListingsSection: some View {
        if !ongoingListings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your listings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)

                VStack(spacing: 10) {
                    ForEach(ongoingListings) { row in
                        if let oppId = row.opportunityId, !oppId.isEmpty {
                            NavigationLink {
                                OpportunityDetailView(opportunityId: oppId)
                            } label: {
                                ongoingListingRow(row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func ongoingListingRow(_ row: InvestmentListing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.opportunityTitle.isEmpty ? "Investment" : row.opportunityTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                if let next = row.nextOpenLoanInstallment {
                    Text("Next: \(scheduleDateLabel(next.dueDate)) · LKR \(formatAmount(next.totalDue))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(row.lifecycleDisplayTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text("LKR \(formatAmount(row.effectiveAmount))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dashboardPink)
                Text(row.lifecycleDisplayTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

// Empty state

    private var emptyExploreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No investments yet")
                .font(.headline)
            Text("Explore opportunities and send your first investment request — your dashboard fills up as deals progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                tabRouter.selectedTab = .action
                tabRouter.investorInvestSegment = .explore
            } label: {
                Text("Explore opportunities")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minTapTarget)
            }
            .buttonStyle(.plain)
            .background(dashboardPink, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .foregroundStyle(.white)
        }
        .padding(AppTheme.cardPadding)
        .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

// Computed dashboard data

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var yearOptions: [Int] {
        Array(((currentYear - 6)...currentYear + 1).reversed())
    }

    private var qualifyingInvestments: [InvestmentListing] {
        investments.filter { inv in
            let s = inv.status.lowercased()
            return !["pending", "declined", "rejected", "cancelled", "withdrawn"].contains(s)
        }
    }

    // Uses the most recent known lifecycle timestamp so chart bucketing reflects when deal activity actually happened.
    private func attributionDate(for inv: InvestmentListing) -> Date? {
        [
            inv.createdAt,
            inv.acceptedAt,
            inv.agreementGeneratedAt,
            inv.signedBySeekerAt,
            inv.signedByInvestorAt
        ]
        .compactMap(\.self)
        .max()
    }

    private func principalAndProjectedGain(for inv: InvestmentListing) -> (principal: Double, gain: Double) {
        let principal = inv.effectiveAmount
        let projected = InvestorPortfolioMetrics.projectedMaturityValue(for: inv)
        return (principal, max(0, projected - principal))
    }

    private func sumPrincipalGain(_ rows: [InvestmentListing]) -> (principal: Double, gain: Double) {
        rows.reduce(into: (0.0, 0.0)) { acc, inv in
            let pair = principalAndProjectedGain(for: inv)
            acc.0 += pair.principal
            acc.1 += pair.gain
        }
    }

    private func investments(inCalendarYear year: Int) -> [InvestmentListing] {
        let cal = Calendar.current
        return qualifyingInvestments.filter {
            guard let d = attributionDate(for: $0) else { return false }
            return cal.component(.year, from: d) == year
        }
    }

    private var selectedQuarter: Int {
        if selectedDashboardYear == currentYear {
            return (Calendar.current.component(.month, from: Date()) - 1) / 3 + 1
        }
        return 4
    }

    private var selectedMonth: Int {
        if selectedDashboardYear == currentYear {
            return Calendar.current.component(.month, from: Date())
        }
        return 12
    }

    private var timelineScopedInvestments: [InvestmentListing] {
        let cal = Calendar.current
        switch earningsPeriod {
        case .annual:
            return investments(inCalendarYear: selectedDashboardYear)
        case .quarterly:
            return qualifyingInvestments.filter { inv in
                guard let d = attributionDate(for: inv) else { return false }
                guard cal.component(.year, from: d) == selectedDashboardYear else { return false }
                let q = (cal.component(.month, from: d) - 1) / 3 + 1
                return q == selectedQuarter
            }
        case .monthly:
            return qualifyingInvestments.filter { inv in
                guard let d = attributionDate(for: inv) else { return false }
                return cal.component(.year, from: d) == selectedDashboardYear && cal.component(.month, from: d) == selectedMonth
            }
        }
    }

    private var selectedYearFinancials: (principal: Double, gain: Double) {
        sumPrincipalGain(timelineScopedInvestments)
    }

    private var totalValue: Double {
        selectedYearFinancials.principal
    }

    private var totalProjectedReturn: Double {
        totalValue + totalProjectedInterest
    }

    private var totalReceived: Double {
        // Year-specific received amount based on investment attribution year.
        timelineScopedInvestments
            .reduce(0) { $0 + InvestorPortfolioMetrics.returnedValue(for: $1) }
    }

    private var totalLiability: Double {
        max(0, totalProjectedReturn - totalReceived)
    }

    // Short label tying the liability figure to the chart period controls.
    private var liabilityStatPeriodSubtitle: String {
        switch earningsPeriod {
        case .annual:
            return "Year \(selectedDashboardYear) · vs projected"
        case .quarterly:
            return "\(selectedDashboardYear) · Q\(selectedQuarter)"
        case .monthly:
            return liabilityMonthYearLabel + " · vs projected"
        }
    }

    private var liabilityMonthYearLabel: String {
        var c = DateComponents()
        c.year = selectedDashboardYear
        c.month = selectedMonth
        c.day = 1
        guard let d = Calendar.current.date(from: c) else { return "\(selectedDashboardYear)" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return f.string(from: d)
    }

    private var totalProjectedInterest: Double {
        selectedYearFinancials.gain
    }

    private var totalInvestedAllTime: Double {
        InvestorPortfolioMetrics.totalInvestedAllTime(investments)
    }

    private var totalReturnsReceived: Double {
        InvestorPortfolioMetrics.receivedTotal(investments)
    }

    private var activeInvestmentsCount: Int {
        InvestorPortfolioMetrics.activeDealsCount(investments)
    }

    private var pendingRequestsCount: Int {
        investments.filter { $0.status.lowercased() == "pending" }.count
    }

    private var ongoingProjectCount: Int {
        let rows = timelineScopedInvestments.filter { InvestorPortfolioMetrics.isOngoingDeal($0) }
        let oppIds = Set(rows.compactMap(\.opportunityId).filter { !$0.isEmpty })
        return oppIds.count
    }

    private var chartBuckets: [InvestorChartBucket] {
        switch earningsPeriod {
        case .annual:
            return ((selectedDashboardYear - 5)...selectedDashboardYear).map { y in
                let sums = sumPrincipalGain(investments(inCalendarYear: y))
                return InvestorChartBucket(id: "y-\(y)", axisLabel: "\(y)", principal: sums.principal, interest: sums.gain)
            }
        case .quarterly:
            let cal = Calendar.current
            return (1...4).map { q in
                let rows = qualifyingInvestments.filter { inv in
                    guard let d = attributionDate(for: inv) else { return false }
                    guard cal.component(.year, from: d) == selectedDashboardYear else { return false }
                    let month = cal.component(.month, from: d)
                    return ((month - 1) / 3 + 1) == q
                }
                let sums = sumPrincipalGain(rows)
                return InvestorChartBucket(id: "q\(q)-\(selectedDashboardYear)", axisLabel: "Q\(q)", principal: sums.principal, interest: sums.gain)
            }
        case .monthly:
            let cal = Calendar.current
            return (1...12).map { m in
                let rows = qualifyingInvestments.filter { inv in
                    guard let d = attributionDate(for: inv) else { return false }
                    return cal.component(.year, from: d) == selectedDashboardYear && cal.component(.month, from: d) == m
                }
                let sums = sumPrincipalGain(rows)
                return InvestorChartBucket(
                    id: "m\(m)-\(selectedDashboardYear)",
                    axisLabel: shortMonthSymbol(m),
                    principal: sums.principal,
                    interest: sums.gain
                )
            }
        }
    }

    private func shortMonthSymbol(_ month: Int) -> String {
        var c = DateComponents()
        c.year = 2000
        c.month = month
        c.day = 1
        guard let d = Calendar.current.date(from: c) else { return "\(month)" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: d)
    }

    private var chartYMax: Double {
        let dataMax = chartBuckets.map(\.total).max() ?? 0
        if dataMax <= 0 { return 1 }
        let padded = dataMax * 1.12
        let pow10 = pow(10, floor(log10(padded)))
        return max(ceil(padded / pow10) * pow10, 1)
    }

    private var chartYTickValues: [Double] {
        let divisions = 5
        return (1...divisions).map { i in
            chartYMax * Double(divisions - i + 1) / Double(divisions + 1)
        }
    }

    private var chartBarWidth: CGFloat {
        switch earningsPeriod {
        case .annual: return 22
        case .quarterly: return 28
        case .monthly: return 14
        }
    }

    private var chartBarSpacing: CGFloat {
        switch earningsPeriod {
        case .annual: return 8
        case .quarterly: return 12
        case .monthly: return 3
        }
    }

    private var chartAxisLabelFont: Font {
        earningsPeriod == .monthly ? .system(size: 8) : .system(size: 10)
    }

    private var chartAxisLabelWidth: CGFloat {
        earningsPeriod == .monthly ? 22 : 28
    }

    private var usesDistributedXAxis: Bool {
        earningsPeriod != .monthly
    }

    private var topRecipients: [TopRecipient] {
        var totals: [String: (amount: Double, count: Int, earliest: Date)] = [:]
        for inv in investments {
            let s = inv.status.lowercased()
            if ["pending", "declined", "rejected", "cancelled", "withdrawn"].contains(s) {
                continue
            }
            guard let sid = inv.seekerId, !sid.isEmpty else { continue }
            let date = inv.acceptedAt ?? inv.createdAt ?? Date()
            var entry = totals[sid] ?? (0, 0, date)
            entry.amount += inv.effectiveAmount
            entry.count += 1
            entry.earliest = min(entry.earliest, date)
            totals[sid] = entry
        }

        let sorted = totals.sorted { $0.value.amount > $1.value.amount }.prefix(5)
        return sorted.map { (sid, entry) in
            let prof = seekerProfiles[sid]
            let displayName: String = {
                if let n = prof?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    return n
                }
                return "Recipient \(String(sid.prefix(4)))"
            }()
            return TopRecipient(
                id: sid,
                displayName: displayName,
                avatarURL: prof?.avatarURL,
                activeSince: entry.earliest,
                dealCount: entry.count,
                totalAmount: entry.amount
            )
        }
    }

    private var ongoingListings: [InvestmentListing] {
        investments
            .filter { InvestorPortfolioMetrics.isOngoingDeal($0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

// Loading

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
            await loadTopRecipientProfiles()
        } catch {
            loadError = FirestoreUserFacingMessage.text(for: error)
        }
    }

    private func loadTopRecipientProfiles() async {
        let seekerIds = Set(
            investments.compactMap { inv -> String? in
                let s = inv.status.lowercased()
                if ["pending", "declined", "rejected", "cancelled", "withdrawn"].contains(s) {
                    return nil
                }
                guard let sid = inv.seekerId, !sid.isEmpty else { return nil }
                return sid
            }
        )
        let missing = seekerIds.subtracting(seekerProfiles.keys)
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: (String, UserProfile?).self) { group in
            for sid in missing {
                group.addTask {
                    let prof = try? await userService.fetchProfile(userID: sid)
                    return (sid, prof)
                }
            }
            for await (sid, prof) in group {
                if let prof {
                    seekerProfiles[sid] = prof
                }
            }
        }
    }

// Formatters

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    private func formatThousandsK(_ value: Double) -> String {
        if value >= 1_000_000 {
            let m = value / 1_000_000
            return m == floor(m) ? "\(Int(m))m" : String(format: "%.1fm", m)
        }
        let k = value / 1_000
        return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
    }

    private func formatBadge(_ amount: Double) -> String {
        let k = amount / 1_000
        if k >= 1 {
            return String(Int(k.rounded()))
        }
        return String(Int(amount.rounded()))
    }

    private func paddedCount(_ count: Int) -> String {
        count < 10 ? String(format: "%02d", count) : String(count)
    }

    private func initials(for name: String) -> String {
        let parts = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let chars = parts.prefix(2).compactMap { $0.first }
        let s = String(chars).uppercased()
        return s.isEmpty ? "?" : s
    }

    private func monthYearLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy MMM"
        return f.string(from: date)
    }

    private func scheduleDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f.string(from: date)
    }

    private func monthsBetween(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b))
        let months = comps.month ?? 0
        let extraDays = comps.day ?? 0
        if months == 0, extraDays > 0 { return 1 }
        return max(0, months)
    }
}

#Preview {
    InvestorDashboardView()
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
}
