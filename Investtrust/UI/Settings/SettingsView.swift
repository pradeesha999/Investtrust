import SwiftUI

/// List content for Settings, embeddable inside any `NavigationStack` (e.g. tab root or pushed from Browse).
struct SettingsContentView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        List {
            Section("Account") {
                Text(auth.currentUserEmail ?? "No email")
                    .font(.subheadline)
            }

            Section {
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
            } header: {
                Text("Active profile")
            } footer: {
                Text("Switching profile updates the Create/Invest tab and defaults you to the Browse tab when a new session starts.")
                    .font(.footnote)
            }

            Section("Session") {
                Button("Sign out", role: .destructive) {
                    auth.signOut()
                }
            }
        }
        .listStyle(.insetGrouped)
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
