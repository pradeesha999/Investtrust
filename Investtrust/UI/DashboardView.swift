import SwiftUI

struct DashboardView: View {
    @Environment(AuthService.self) private var auth
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome")
                    .font(.title.bold())
                Text(auth.currentUserEmail ?? "Signed in user")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("Current profile: \(auth.activeProfile == .investor ? "Investor" : "Opportunity Seeker")")
                    .font(.headline)
                    .padding(.top, 8)
                
                Text("Use the tabs below to invest, create opportunities, chat, and manage settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
        }
    }
}

#Preview {
    DashboardView()
        .environment(AuthService.previewSignedIn)
}
