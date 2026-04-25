import SwiftUI

/// Investor **Invest** tab: segmented **My requests** (statuses) vs **Explore** (market listings).
struct InvestorActionTabView: View {
    @EnvironmentObject private var tabRouter: MainTabRouter

    private var segmentBinding: Binding<InvestorInvestSegment> {
        Binding(
            get: { tabRouter.investorInvestSegment },
            set: { tabRouter.investorInvestSegment = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Invest mode", selection: segmentBinding) {
                    ForEach(InvestorInvestSegment.allCases, id: \.self) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 10)

                Text(tabRouter.investorInvestSegment == .myRequests ? "Your submitted requests and agreement status." : "Explore market listings and filters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.bottom, 8)

                Group {
                    switch tabRouter.investorInvestSegment {
                    case .myRequests:
                        InvestorMarketView()
                    case .explore:
                        MarketBrowseView(embeddedInInvestTab: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invest")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    InvestorActionTabView()
        .environment(AuthService.previewSignedIn)
        .environmentObject(MainTabRouter())
}
