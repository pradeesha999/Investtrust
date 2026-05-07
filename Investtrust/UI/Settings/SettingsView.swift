import SwiftUI

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
