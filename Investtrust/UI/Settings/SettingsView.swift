import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Text(auth.currentUserEmail ?? "No email")
                        .font(.subheadline)
                }
                
                Section("Active Profile") {
                    Picker("Profile", selection: profileBinding) {
                        if auth.roles.investor {
                            Text("Investor")
                                .tag(UserProfile.ActiveProfile.investor)
                        }
                        if auth.roles.seeker {
                            Text("Opportunity Seeker")
                                .tag(UserProfile.ActiveProfile.seeker)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("Choose a profile from the menu. After switching, you’ll return to the Dashboard.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Session") {
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private var profileBinding: Binding<UserProfile.ActiveProfile> {
        Binding(
            get: { auth.activeProfile },
            set: { newValue in
                Task {
                    await auth.switchActiveProfile(newValue)
                }
            }
        )
    }
}

#Preview {
    SettingsView()
        .environment(AuthService.previewSignedIn)
}
