import SwiftUI

// The Home tab — shows either the investor portfolio dashboard or the seeker's home screen
// depending on the user's active profile mode
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
