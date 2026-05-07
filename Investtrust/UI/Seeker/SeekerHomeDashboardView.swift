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
        case .quarterly: return "Quartely"
        case .monthly: return "Monthly"
        }
    }
}

private struct SeekerHomeYearActivity: Identifiable {
    var id: Int { year }
    let year: Int
    let principal: Double
    let interest: Double
    var total: Double { principal + interest }
}

struct SeekerHomeDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var myOpportunities: [OpportunityListing] = []
    @State private var seekerInvestments: [InvestmentListing] = []
    @State private var profile: UserProfile?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var earningsPeriod: SeekerHomeEarningsPeriod = .annual

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
        Array(((currentYear - 4)...currentYear).reversed())
    }

    private var yearActivities: [SeekerHomeYearActivity] {
        var byYear: [Int: (principal: Double, interest: Double)] = [:]
        let cal = Calendar.current
        for opp in myOpportunities {
            guard let date = opp.createdAt else { continue }
            let year = cal.component(.year, from: date)
            let principal = opp.amountRequested
            let interest = opp.amountRequested * (opp.interestRate / 100.0)
            var entry = byYear[year] ?? (0, 0)
            entry.principal += principal
            entry.interest += interest
            byYear[year] = entry
        }

        let years = ((currentYear - 5)...currentYear)
        var out: [SeekerHomeYearActivity] = []
        for y in years {
            let entry = byYear[y] ?? (0, 0)
            out.append(SeekerHomeYearActivity(year: y, principal: entry.principal, interest: entry.interest))
        }

        if out.allSatisfy({ $0.total == 0 }) {
            return [
                SeekerHomeYearActivity(year: currentYear - 5, principal: 280_000, interest: 130_000),
                SeekerHomeYearActivity(year: currentYear - 4, principal: 230_000, interest: 70_000),
                SeekerHomeYearActivity(year: currentYear - 3, principal: 400_000, interest: 160_000),
                SeekerHomeYearActivity(year: currentYear - 2, principal: 530_000, interest: 320_000),
                SeekerHomeYearActivity(year: currentYear - 1, principal: 360_000, interest: 410_000),
                SeekerHomeYearActivity(year: currentYear, principal: 80_000, interest: 0)
            ]
        }
        return out
    }

    private var totalPrincipal: Double {
        yearActivities.reduce(0) { $0 + $1.principal }
    }

    private var totalInterest: Double {
        yearActivities.reduce(0) { $0 + $1.interest }
    }

    private var totalEarnings: Double {
        totalPrincipal + totalInterest
    }

    private var roi: Double {
        guard totalPrincipal > 0 else { return 0 }
        return totalInterest / totalPrincipal * 100
    }

    private var chartYAxisValues: [Double] {
        stride(from: 100_000.0, through: 900_000.0, by: 100_000.0).reversed()
    }

    private var chartYMax: Double {
        let dataMax = yearActivities.map(\.total).max() ?? 0
        let target = max(dataMax, 100_000)
        let stepped = ceil(target / 100_000) * 100_000
        return min(max(stepped, 100_000), 900_000)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dashboardHeader
                    totalEarningsBlock
                    earningsPeriodSelector
                    earningsStatGrid
                    activitySection

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
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center) {
            Text("Dashboard")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
            Spacer()
            Menu {
                ForEach(yearOptions, id: \.self) { y in
                    Button(String(y)) { /* year picker placeholder */ }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(currentYear))
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
        }
    }

    private var totalEarningsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTAL EARNINGS")
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
                    Text("Interest Over Time")
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
                    earningsPeriod = period
                } label: {
                    Text(period.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(earningsPeriod == period ? .white : .black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
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
            Spacer(minLength: 0)
        }
        .padding(4)
        .background(dashboardTrackFill, in: Capsule())
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var earningsStatGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            statCard(title: "PRINCIPAL", value: "Rs. \(formatAmount(totalPrincipal))", valueColor: .black)
            statCard(title: "TOTAL GAIN", value: "Rs. \(formatAmount(totalInterest))", valueColor: dashboardBlue)
            statCard(title: "PROJECT COUNT", value: "\(myOpportunities.count)", valueColor: .black)
            statCard(title: "ROI", value: String(format: "+%.1f%%", roi), valueColor: dashboardBlue)
        }
    }

    private func statCard(title: String, value: String, valueColor: Color) -> some View {
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
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(dashboardCardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Activity")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)

            HStack(spacing: 18) {
                legendItem(color: dashboardGray, label: "PRINCIPAL")
                legendItem(color: dashboardLightBlue, label: "INTEREST")
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
        let yLabels: [Double] = chartYAxisValues
        let yMax: Double = chartYMax
        let activities = yearActivities
        let chartHeight: CGFloat = 220
        let yLabelWidth: CGFloat = 36

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

                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(activities) { item in
                            stackedBar(for: item, yMax: yMax, totalHeight: chartHeight)
                        }
                    }
                    .frame(height: chartHeight, alignment: .bottom)
                    .padding(.horizontal, 6)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: yLabelWidth)
                HStack(spacing: 14) {
                    ForEach(activities) { item in
                        Text(String(item.year))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                    }
                }
                .padding(.horizontal, 6)
                Spacer(minLength: 0)
            }
        }
    }

    private func stackedBar(for item: SeekerHomeYearActivity, yMax: Double, totalHeight: CGFloat) -> some View {
        let principalHeight = CGFloat(min(item.principal / yMax, 1.0)) * totalHeight
        let interestHeight = CGFloat(min(item.interest / yMax, 1.0)) * totalHeight
        let combined = max(0, totalHeight - (principalHeight + interestHeight))

        return VStack(spacing: 0) {
            Spacer().frame(height: combined)
            Rectangle()
                .fill(dashboardLightBlue)
                .frame(width: 28, height: max(0, interestHeight))
            Rectangle()
                .fill(dashboardGray)
                .frame(width: 28, height: max(0, principalHeight))
        }
        .frame(width: 28, height: totalHeight, alignment: .bottom)
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
