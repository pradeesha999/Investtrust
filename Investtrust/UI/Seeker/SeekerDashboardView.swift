//
//  SeekerDashboardView.swift
//  Investtrust
//

import SwiftUI

struct SeekerDashboardView: View {
    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var showCreateFlow = false
    @State private var myOpportunities: [OpportunityListing] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let opportunityService = OpportunityService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError {
                        errorBanner(loadError)
                    } else if isLoading && myOpportunities.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(60)
                    } else if myOpportunities.isEmpty {
                        emptyStateCard
                    } else {
                        listingsHeader
                        LazyVStack(spacing: 16) {
                            ForEach(myOpportunities) { item in
                                NavigationLink {
                                    SeekerOpportunityDetailView(opportunity: item) {
                                        Task { await loadMyOpportunities() }
                                    }
                                } label: {
                                    listingCard(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Opportunity")
            .task { await loadMyOpportunities() }
            .refreshable { await loadMyOpportunities() }
            .onAppear { consumeExternalCreateWizardIntentIfNeeded() }
            .onChange(of: tabRouter.openSeekerCreateWizard) { _, _ in
                consumeExternalCreateWizardIntentIfNeeded()
            }
            .sheet(isPresented: $showCreateFlow) {
                CreateOpportunityWizardView { draft, imageDataList, videoData in
                    guard let userID = auth.currentUserID else {
                        throw NSError(domain: "Investtrust", code: 401,
                                      userInfo: [NSLocalizedDescriptionKey: "Please sign in again."])
                    }
                    _ = try await opportunityService.createOpportunity(
                        userID: userID, draft: draft,
                        imageDataList: imageDataList, videoData: videoData
                    )
                    await loadMyOpportunities()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !myOpportunities.isEmpty {
                    Button { showCreateFlow = true } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                            .frame(width: 56, height: 56)
                            .background(auth.accentColor, in: Circle())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, AppTheme.screenPadding)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Data

    private func loadMyOpportunities() async {
        guard let userID = auth.currentUserID else { return }
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            myOpportunities = try await opportunityService.fetchSeekerListings(ownerId: userID)
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func consumeExternalCreateWizardIntentIfNeeded() {
        guard tabRouter.openSeekerCreateWizard else { return }
        tabRouter.openSeekerCreateWizard = false
        showCreateFlow = true
    }

    // MARK: - Chrome

    private var listingsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("My listings")
                .font(.title3.bold())
            Spacer()
            Text("\(myOpportunities.count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(auth.accentColor)
            + Text(" total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(auth.accentColor.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(auth.accentColor)
            }
            .padding(.top, 8)
            VStack(spacing: 6) {
                Text("No listings yet")
                    .font(.title3.bold())
                Text("Publish your first investment request and start receiving offers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { showCreateFlow = true } label: {
                Label("Add opportunity", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minTapTarget)
                    .background(auth.accentColor,
                                in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(AppTheme.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }

    // MARK: - Listing card

    private func listingCard(_ item: OpportunityListing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Thumbnail strip with overlaid chips ──────────────────
            thumbnailStrip(item)

            // ── Body ─────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 14) {
                // Title row
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !item.category.isEmpty {
                            Text(item.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    // Rate badge ─ always visible for loan
                    if item.investmentType == .loan, item.interestRate > 0 {
                        VStack(spacing: 1) {
                            Text("\(formatRate(item.interestRate))%")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(auth.accentColor)
                            Text("p.a.")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(auth.accentColor.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(auth.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                // ── Financial panel ───────────────────────────────────
                financialPanel(for: item)

                // ── Footer meta ───────────────────────────────────────
                HStack(spacing: 0) {
                    if let m = item.terms.repaymentTimelineMonths, m > 0,
                       item.investmentType == .loan {
                        metaTag(label: "\(m) months")
                    }
                    metaTag(label: item.maximumInvestors.map { "\($0) investor\($0 == 1 ? "" : "s")" } ?? "Open round")
                    if let d = item.createdAt {
                        Spacer()
                        Text(shortDate(d))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(AppTheme.cardPadding)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
        .appCardShadow()
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func thumbnailStrip(_ item: OpportunityListing) -> some View {
        ZStack(alignment: .bottom) {
            // Image / placeholder
            if let first = item.imageStoragePaths.first {
                StorageBackedAsyncImage(
                    reference: first,
                    height: 140,
                    cornerRadius: 0,
                    feedThumbnail: true
                )
                .frame(maxWidth: .infinity)
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [auth.accentColor.opacity(0.25), auth.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 80)
                    .overlay {
                        Image(systemName: investmentTypeIcon(item.investmentType))
                            .font(.system(size: 32))
                            .foregroundStyle(auth.accentColor.opacity(0.45))
                    }
            }

            // Bottom chip bar
            HStack(spacing: 6) {
                chipBadge(item.investmentType.displayName,
                          fg: .white,
                          bg: Color.black.opacity(0.55))
                Spacer()
                chipBadge(item.status.capitalized,
                          fg: statusColor(item.status),
                          bg: Color.white.opacity(0.92))
            }
            .padding(10)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: AppTheme.cardCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: AppTheme.cardCornerRadius,
                style: .continuous
            )
        )
    }

    // MARK: - Financial panel

    @ViewBuilder
    private func financialPanel(for item: OpportunityListing) -> some View {
        if item.investmentType == .loan, let outcome = loanOutcome(for: item) {
            loanFinancialPanel(item: item, outcome: outcome)
        } else {
            genericFinancialPanel(for: item)
        }
    }

    private func loanFinancialPanel(
        item: OpportunityListing,
        outcome: OpportunityFinancialPreview.LoanMoneyOutcome
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Total repayable — headline number
            VStack(alignment: .leading, spacing: 2) {
                Text("Investors receive back")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("LKR \(OpportunityFinancialPreview.formatLKRInteger(outcome.totalRepayable))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            // Principal + Interest side-by-side
            HStack(spacing: 10) {
                // Principal
                VStack(alignment: .leading, spacing: 3) {
                    Text("Principal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("LKR \(item.formattedAmountLKR)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.secondaryFill,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Interest (profit to investor)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.green)
                        Text("Interest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.green.opacity(0.85))
                    }
                    Text("+ LKR \(OpportunityFinancialPreview.formatLKRInteger(outcome.interestAmount))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(AppTheme.secondaryFill.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func genericFinancialPanel(for item: OpportunityListing) -> some View {
        HStack(spacing: 10) {
            financialPanelTile(
                label: "Funding goal",
                value: "LKR \(item.formattedAmountLKR)",
                tint: .primary,
                bg: AppTheme.secondaryFill
            )
            financialPanelTile(
                label: typeMetricTitle(for: item.investmentType),
                value: typeMetricValue(for: item),
                tint: auth.accentColor,
                bg: auth.accentColor.opacity(0.10)
            )
        }
    }

    private func financialPanelTile(label: String, value: String, tint: Color, bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Meta

    private func metaTag(label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.secondaryFill, in: Capsule())
            .padding(.trailing, 6)
    }

    private func chipBadge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
    }

    // MARK: - Helpers

    private func loanOutcome(for item: OpportunityListing) -> OpportunityFinancialPreview.LoanMoneyOutcome? {
        guard item.investmentType == .loan,
              let rate = item.terms.interestRate, rate > 0,
              let months = item.terms.repaymentTimelineMonths, months > 0,
              item.amountRequested > 0 else { return nil }
        return OpportunityFinancialPreview.loanMoneyOutcome(
            principal: item.amountRequested,
            annualRatePercent: rate,
            termMonths: months,
            plan: LoanRepaymentPlan.from(item.terms.repaymentFrequency)
        )
    }

    private func typeMetricTitle(for type: InvestmentType) -> String {
        switch type {
        case .equity: return "Equity offered"
        case .revenue_share: return "Rev. share"
        case .project: return "Expected return"
        case .custom: return "Structure"
        case .loan: return "Min ticket"
        }
    }

    private func typeMetricValue(for item: OpportunityListing) -> String {
        switch item.investmentType {
        case .equity:
            if let p = item.terms.equityPercentage, p > 0 { return "\(formatRate(p))%" }
        case .revenue_share:
            if let p = item.terms.revenueSharePercent, p > 0 { return "\(formatRate(p))%" }
        case .project:
            let v = (item.terms.expectedReturnValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        case .custom:
            return "Custom"
        case .loan:
            return "LKR \(item.formattedMinimumLKR)"
        }
        return "—"
    }

    private func investmentTypeIcon(_ type: InvestmentType) -> String {
        switch type {
        case .loan: return "banknote"
        case .equity: return "chart.pie"
        case .revenue_share: return "arrow.triangle.2.circlepath"
        case .project: return "hammer"
        case .custom: return "doc.text"
        }
    }

    private func formatRate(_ rate: Double) -> String {
        rate == floor(rate) ? String(Int(rate)) : String(format: "%.1f", rate)
    }

    private func statusColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "open": return .green
        case "closed", "filled", "funded": return .secondary
        default: return .primary
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }
}

#Preview {
    SeekerDashboardView()
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
}
