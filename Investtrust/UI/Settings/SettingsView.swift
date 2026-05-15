import SwiftUI

// Settings tab root — wraps SettingsContentView in a NavigationStack
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            SettingsContentView()
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthService.previewSignedIn)
}
