import SwiftUI

/// First tab: investor portfolio home, or seeker market browse (seeker-specific home TBD).
struct DashboardView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.activeProfile == .investor {
                InvestorDashboardView()
            } else {
                NavigationStack {
                    MarketBrowseView()
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(AuthService.previewSignedIn)
}
