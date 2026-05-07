import SwiftUI

/// First tab: investor portfolio home, or seeker owner home (capital + activity).
struct DashboardView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.activeProfile == .investor {
                InvestorDashboardView()
            } else {
                SeekerHomeDashboardView()
            }
        }
        .accessibilityHint(
            auth.activeProfile == .investor
                ? "Showing the investor dashboard."
                : "Showing the opportunity builder dashboard."
        )
    }
}

#Preview {
    DashboardView()
        .environment(AuthService.previewSignedIn)
}
