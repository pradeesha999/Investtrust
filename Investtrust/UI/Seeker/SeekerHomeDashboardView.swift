//
//  SeekerHomeDashboardView.swift
//  Investtrust
//
//  Seeker **Home** tab: capital overview, investor activity, and listings.
//

import SwiftUI

private enum SeekerHomeEarningsPeriod: String, CaseIterable {
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

private struct SeekerHomeChartBucket: Identifiable {
    let id: String
    let axisLabel: String
    let principal: Double
    let interest: Double
    var total: Double { principal + interest }
}

private struct SeekerTopInvestor: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String?
    let totalAmount: Double
    let dealsCount: Int
    let sinceDate: Date
}

struct SeekerHomeDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var myOpportunities: [OpportunityListing] = []
    @State private var seekerInvestments: [InvestmentListing] = []
    @State private var profile: UserProfile?
    @State private var investorProfiles: [String: UserProfile] = [:]
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var earningsPeriod: SeekerHomeEarningsPeriod = .annual
    @State private var selectedDashboardYear: Int = Calendar.current.component(.year, from: Date())
    @State private var hasInitializedYearSelection = false

    private let opportunityService = OpportunityService()
    private let investmentService = InvestmentService()
    private let userService = UserService()

    private let dashboardBlue = Color(red: 0.0, green: 122.0 / 255.0, blue: 1.0)
    private let dashboardLightBlue = Color(red: 0.78, green: 0.88, blue: 1.0)
    private let dashboardCardFill = Color(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0)
    private let dashboardTrackFill = Color(red: 229.0 / 255.0, green: 229.0 / 255.0, blue: 234.0 / 255.0)
    private let dashboardGray = Color(red: 217.0 / 255.0, green: 217.0 / 255.0, blue: 217.0 / 255.0)
    private let dashboardOutline = Color(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 147.0 / 255.0)

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

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var yearOptions: [Int] {
        Array(((currentYear - 6)...currentYear + 1).reversed())
    }

    /// Investments that affect seeker financial metrics (must be accepted/active/completed, not just pending requests).
    private var qualifyingInvestments: [InvestmentListing] {
        seekerInvestments.filter { inv in
            let s = inv.status.lowercased()
            if isDeclinedLike(inv) || s == "pending" { return false }
            return true
        }
    }

    /// Uses the most recent known lifecycle timestamp so chart bucketing reflects when deal activity actually happened.
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

    /// Seeker view semantics:
    /// - principal = capital received
    /// - gain = liability still owed to investors (projected return - already repaid)
    private func principalAndProjectedGain(for inv: InvestmentListing) -> (principal: Double, gain: Double) {
        let principal = inv.investmentAmount
        let projected = InvestorPortfolioMetrics.projectedMaturityValue(for: inv)
        let repaid = InvestorPortfolioMetrics.returnedValue(for: inv)
        let outstanding = max(0, projected - repaid)
        return (principal, outstanding)
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

    private var ongoingInvestments: [InvestmentListing] {
        timelineScopedInvestments.filter { InvestorPortfolioMetrics.isOngoingDeal($0) }
    }

    private var completedInvestments: [InvestmentListing] {
        timelineScopedInvestments.filter { InvestorPortfolioMetrics.isCompletedDeal($0) }
    }

    private var activeInvestmentsCount: Int {
        ongoingInvestments.count
    }

    private var pendingRequestsCount: Int {
        let cal = Calendar.current
        return seekerInvestments.filter { inv in
            guard inv.status.lowercased() == "pending" else { return false }
            let date = attributionDate(for: inv) ?? inv.createdAt
            guard let date else { return false }
            switch earningsPeriod {
            case .annual:
                return cal.component(.year, from: date) == selectedDashboardYear
            case .quarterly:
                guard cal.component(.year, from: date) == selectedDashboardYear else { return false }
                let q = (cal.component(.month, from: date) - 1) / 3 + 1
                return q == selectedQuarter
            case .monthly:
                return cal.component(.year, from: date) == selectedDashboardYear
                    && cal.component(.month, from: date) == selectedMonth
            }
        }.count
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

    /// KPI cards + headline: totals for selected timeline scope.
    private var selectedYearFinancials: (principal: Double, gain: Double, fundedProjectCount: Int) {
        let rows = timelineScopedInvestments
        let sums = sumPrincipalGain(rows)
        let oppIds = Set(rows.compactMap(\.opportunityId).filter { !$0.isEmpty })
        return (sums.principal, sums.gain, oppIds.count)
    }

    private var totalPrincipal: Double {
        selectedYearFinancials.principal
    }

    private var totalInterest: Double {
        selectedYearFinancials.gain
    }

    /// Primary headline: total capital received for selected timeline.
    private var totalEarnings: Double {
        totalPrincipal
    }

    private var ongoingProjectCount: Int {
        Set(ongoingInvestments.compactMap(\.opportunityId).filter { !$0.isEmpty }).count
    }

    private var completedProjectCount: Int {
        Set(completedInvestments.compactMap(\.opportunityId).filter { !$0.isEmpty }).count
    }

    private var dashboardProjectCount: Int {
        let funded = selectedYearFinancials.fundedProjectCount
        if funded > 0 { return funded }
        let cal = Calendar.current
        return myOpportunities.filter {
            guard let d = $0.createdAt else { return false }
            return cal.component(.year, from: d) == selectedDashboardYear
        }.count
    }

    private var nextPaymentInfo: (title: String, amount: Double, days: Int)? {
        let today = Calendar.current.startOfDay(for: Date())
        let upcoming = InvestorPortfolioMetrics
            .upcomingPayments(withinDays: 3650, rows: ongoingInvestments)
            .first(where: { Calendar.current.startOfDay(for: $0.date) >= today })
        guard let upcoming else { return nil }
        let days = max(0, Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: upcoming.date)).day ?? 0)
        return (upcoming.title, upcoming.amount, days)
    }

    private var topInvestors: [SeekerTopInvestor] {
        var totals: [String: (amount: Double, deals: Int, earliest: Date)] = [:]
        for inv in qualifyingInvestments {
            guard let iid = inv.investorId, !iid.isEmpty else { continue }
            guard let d = attributionDate(for: inv) else { continue }
            var entry = totals[iid] ?? (0, 0, d)
            entry.amount += inv.investmentAmount
            entry.deals += 1
            entry.earliest = min(entry.earliest, d)
            totals[iid] = entry
        }

        return totals
            .sorted { $0.value.amount > $1.value.amount }
            .prefix(5)
            .map { iid, entry in
                let prof = investorProfiles[iid]
                let name = (prof?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? prof?.displayName ?? "Investor"
                    : "Investor \(String(iid.prefix(4)))"
                return SeekerTopInvestor(
                    id: iid,
                    displayName: name,
                    avatarURL: prof?.avatarURL,
                    totalAmount: entry.amount,
                    dealsCount: entry.deals,
                    sinceDate: entry.earliest
                )
            }
    }

    /// Chart buckets depend on **Annual / Quarterly / Monthly** (same underlying deals; different grouping).
    private var chartBuckets: [SeekerHomeChartBucket] {
        switch earningsPeriod {
        case .annual:
            var buckets: [SeekerHomeChartBucket] = []
            for y in (selectedDashboardYear - 5)...selectedDashboardYear {
                let rows = investments(inCalendarYear: y)
                let sums = sumPrincipalGain(rows)
                buckets.append(
                    SeekerHomeChartBucket(id: "y-\(y)", axisLabel: "\(y)", principal: sums.principal, interest: sums.gain)
                )
            }
            return buckets
        case .quarterly:
            let cal = Calendar.current
            return (1...4).map { q in
                let rows = qualifyingInvestments.filter { inv in
                    guard let d = attributionDate(for: inv) else { return false }
                    guard cal.component(.year, from: d) == selectedDashboardYear else { return false }
                    let month = cal.component(.month, from: d)
                    let iq = (month - 1) / 3 + 1
                    return iq == q
                }
                let sums = sumPrincipalGain(rows)
                return SeekerHomeChartBucket(id: "q\(q)-\(selectedDashboardYear)", axisLabel: "Q\(q)", principal: sums.principal, interest: sums.gain)
            }
        case .monthly:
            let cal = Calendar.current
            return (1...12).map { month in
                let rows = qualifyingInvestments.filter { inv in
                    guard let d = attributionDate(for: inv) else { return false }
                    guard cal.component(.year, from: d) == selectedDashboardYear else { return false }
                    return cal.component(.month, from: d) == month
                }
                let sums = sumPrincipalGain(rows)
                return SeekerHomeChartBucket(
                    id: "m\(month)-\(selectedDashboardYear)",
                    axisLabel: shortMonthSymbol(month),
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
        guard let date = Calendar.current.date(from: c) else { return "\(month)" }
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: date)
    }

    private var chartYMax: Double {
        let dataMax = chartBuckets.map(\.total).max() ?? 0
        if dataMax <= 0 { return 1 }
        let padded = dataMax * 1.12
        let pow10 = pow(10, floor(log10(padded)))
        let upper = ceil(padded / pow10) * pow10
        return max(upper, 1)
    }

    /// Top → bottom grid labels (exclude 0 to avoid clutter at baseline).
    private var chartYTickValues: [Double] {
        let maxV = chartYMax
        let divisions = 5
        return (1...divisions).map { i in
            maxV * Double(divisions - i + 1) / Double(divisions + 1)
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

    private func openOpportunitySegment(_ segment: SeekerOpportunitySegment) {
        tabRouter.seekerOpportunitySegment = segment
        tabRouter.selectedTab = .action
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dashboardHeader
                    totalEarningsBlock
                    earningsPeriodSelector
                    earningsStatGrid
                    projectStatusQuickLinks
                    activitySection
                    nextPaymentCard
                    topInvestorsSection

                    if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(AppTheme.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                            .appCardShadow()
                    }

                    if !myOpportunities.isEmpty {
                        Text("Your listings")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.top, 4)

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
                    } else if myOpportunities.isEmpty && seekerInvestments.isEmpty && !isLoading {
                        emptyStateCreateCard
                    }
                }
                .padding(AppTheme.screenPadding)
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadHomeData() }
            .refreshable { await loadHomeData() }
            .onAppear {
                guard !hasInitializedYearSelection else { return }
                selectedDashboardYear = currentYear
                hasInitializedYearSelection = true
            }
        }
    }

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

    private var totalEarningsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTAL RECEIVED")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .tracking(0.5)

            HStack(alignment: .center, spacing: 12) {
                Text("Rs. \(formatAmount(totalEarnings))")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(dashboardBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                VStack(alignment: .center, spacing: 4) {
                    Text("+Rs. \(formatThousandsK(totalInterest))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(dashboardBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(dashboardLightBlue.opacity(0.55), in: Capsule())
                    Text("Liability To Settle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var earningsPeriodSelector: some View {
        HStack(spacing: 4) {
            ForEach(SeekerHomeEarningsPeriod.allCases, id: \.self) { period in
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
                                    Capsule().fill(dashboardBlue)
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

    private var earningsStatGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            statCard(title: "RECEIVED AMOUNT", value: "Rs. \(formatAmount(totalPrincipal))", valueColor: .black)
            statCard(title: "LIABILITY DUE", value: "Rs. \(formatAmount(totalInterest))", valueColor: dashboardBlue)
            statCard(title: "ACTIVE INVESTMENTS", value: "\(activeInvestmentsCount)", valueColor: .black)
            statCard(title: "PENDING REQUESTS", value: "\(pendingRequestsCount)", valueColor: dashboardBlue)
        }
    }

    @ViewBuilder
    private func statCard(title: String, value: String, valueColor: Color, action: (() -> Void)? = nil) -> some View {
        let card = VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .tracking(0.4)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if action != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }

        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var nextPaymentCard: some View {
        Group {
            if let next = nextPaymentInfo {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(dashboardBlue)
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
                        .foregroundStyle(dashboardBlue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var topInvestorsSection: some View {
        let rows = topInvestors
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top Investors")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)

                VStack(spacing: 10) {
                    ForEach(rows) { investor in
                        topInvestorRow(investor)
                    }
                }
            }
        }
    }

    private func topInvestorRow(_ investor: SeekerTopInvestor) -> some View {
        HStack(spacing: 12) {
            topInvestorAvatar(investor)
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(investor.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Text("Deals: \(investor.dealsCount) · Since \(monthYearLabel(investor.sinceDate))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Text("Rs. \(formatThousandsK(investor.totalAmount))")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(dashboardBlue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func topInvestorAvatar(_ investor: SeekerTopInvestor) -> some View {
        if let url = investor.avatarURL, !url.isEmpty {
            StorageBackedAsyncImage(
                reference: url,
                height: 42,
                cornerRadius: 21,
                feedThumbnail: true
            )
            .frame(width: 42, height: 42)
        } else {
            ZStack {
                Circle().fill(dashboardBlue.opacity(0.14))
                Text(initials(for: investor.displayName))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(dashboardBlue)
            }
        }
    }

    private var projectStatusQuickLinks: some View {
        VStack(spacing: 10) {
            quickStatusLink(
                title: "Ongoing projects",
                count: ongoingProjectCount,
                tint: dashboardBlue,
                action: { openOpportunitySegment(.ongoing) }
            )
            quickStatusLink(
                title: "Completed projects",
                count: completedProjectCount,
                tint: .secondary,
                action: { openOpportunitySegment(.completed) }
            )
        }
    }

    private func quickStatusLink(title: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Activity")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)

            HStack(spacing: 18) {
                legendItem(color: dashboardGray, label: "RECEIVED")
                legendItem(color: dashboardLightBlue, label: "LIABILITY")
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
        let yTicks = chartYTickValues
        let yMax = chartYMax
        let buckets = chartBuckets
        let chartHeight: CGFloat = 220
        let yLabelWidth: CGFloat = 40
        let barW = chartBarWidth
        let barGap = chartBarSpacing

        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(yTicks, id: \.self) { v in
                        Text(axisTickLabel(v))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: yLabelWidth, height: chartHeight)

                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        ForEach(yTicks.indices, id: \.self) { _ in
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
                                ForEach(buckets) { item in
                                    stackedBar(for: item, yMax: yMax, totalHeight: chartHeight, barWidth: barW)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        } else {
                            HStack(alignment: .bottom, spacing: barGap) {
                                ForEach(buckets) { item in
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
                            ForEach(buckets) { item in
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
                            ForEach(buckets) { item in
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

    private func axisTickLabel(_ value: Double) -> String {
        if value >= 1_000_000 {
            let m = value / 1_000_000
            return m == floor(m) ? "\(Int(m))m" : String(format: "%.1fm", m)
        }
        if value >= 1000 {
            let k = value / 1000
            return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        if value == floor(value) {
            return "\(Int(value))"
        }
        return String(format: "%.0f", value)
    }

    private func stackedBar(for item: SeekerHomeChartBucket, yMax: Double, totalHeight: CGFloat, barWidth: CGFloat) -> some View {
        let principalHeight = CGFloat(min(item.principal / yMax, 1.0)) * totalHeight
        let interestHeight = CGFloat(min(item.interest / yMax, 1.0)) * totalHeight
        let combined = max(0, totalHeight - (principalHeight + interestHeight))

        return VStack(spacing: 0) {
            Spacer().frame(height: combined)
            Rectangle()
                .fill(dashboardLightBlue)
                .frame(width: barWidth, height: max(0, interestHeight))
            Rectangle()
                .fill(dashboardGray)
                .frame(width: barWidth, height: max(0, principalHeight))
        }
        .frame(width: barWidth, height: totalHeight, alignment: .bottom)
    }

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

    // MARK: - Overview

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingLine)
                .font(.title2.bold())
            Text("Seeker dashboard")
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
            Text("Overview")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                metricTile(
                    value: "\(openListingsCount)",
                    label: "Open listings"
                )
                metricTile(
                    value: "\(pendingReviewCount)",
                    label: "Pending requests"
                )
                metricTile(
                    value: "\(awaitingSignaturesCount)",
                    label: "Awaiting signatures"
                )
            }

            HStack(spacing: 10) {
                metricTile(
                    value: "\(liveDealsCount)",
                    label: "Active agreements"
                )
                metricTile(
                    value: "\(principalConfirmationNeededCount)",
                    label: "Principal pending"
                )
                metricTile(
                    value: "\(completedDealsCount)",
                    label: "Completed deals"
                )
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
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

    private func metricTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
            await loadTopInvestorProfiles()
        } catch {
            profile = nil
            loadError = FirestoreUserFacingMessage.text(for: error)
        }
    }

    private func loadTopInvestorProfiles() async {
        let investorIds = Set(
            qualifyingInvestments.compactMap { inv -> String? in
                guard let iid = inv.investorId, !iid.isEmpty else { return nil }
                return iid
            }
        )
        let missing = investorIds.subtracting(investorProfiles.keys)
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: (String, UserProfile?).self) { group in
            for iid in missing {
                group.addTask {
                    let prof = try? await userService.fetchProfile(userID: iid)
                    return (iid, prof)
                }
            }
            for await (iid, prof) in group {
                if let prof {
                    investorProfiles[iid] = prof
                }
            }
        }
    }

    private func homeListingRow(_ item: OpportunityListing) -> some View {
        let pending = pendingCount(for: item.id)
        let live = seekerInvestments.contains {
            $0.opportunityId == item.id && ($0.agreementStatus == .active || $0.status.lowercased() == "active")
        }
        let committed = committedPrincipal(for: item.id)

        return VStack(alignment: .leading, spacing: 12) {
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
                    .lineLimit(1)
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
