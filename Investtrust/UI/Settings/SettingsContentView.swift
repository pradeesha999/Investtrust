import SwiftUI

/// List content for Settings, embeddable inside any `NavigationStack` (e.g. tab root or pushed from Browse).
struct SettingsContentView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        List {
            Section("Account") {
                Text(auth.currentUserEmail ?? "No email")
                    .font(.subheadline)

                NavigationLink {
                    ProfileEditView()
                } label: {
                    Label("Your profile", systemImage: "person.crop.circle")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How you use Investtrust")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if auth.roles.investor {
                            roleCard(
                                title: "Investor",
                                subtitle: "Browse & invest",
                                systemImage: "chart.line.uptrend.xyaxis",
                                role: .investor
                            )
                        }
                        if auth.roles.seeker {
                            roleCard(
                                title: "Opportunity builder",
                                subtitle: "Create & raise",
                                systemImage: "building.columns.fill",
                                role: .seeker
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Active mode")
            } footer: {
                Text("The tab bar highlights Create vs Invest based on this. You can change it anytime.")
                    .font(.footnote)
            }

            Section("Preferences") {
                NavigationLink {
                    SettingsAppearanceView()
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

                NavigationLink {
                    SettingsLanguageView()
                } label: {
                    Label("Language", systemImage: "globe")
                }

                NavigationLink {
                    SettingsAccessibilityView()
                } label: {
                    Label("Accessibility", systemImage: "accessibility")
                }
            }

            Section("Support") {
                NavigationLink {
                    SettingsHelpCenterView()
                } label: {
                    Label("Help center", systemImage: "questionmark.circle")
                }

                NavigationLink {
                    SettingsContactUsView()
                } label: {
                    Label("Contact us", systemImage: "envelope")
                }

                NavigationLink {
                    SettingsTermsView()
                } label: {
                    Label("Terms & conditions", systemImage: "doc.text")
                }
            }

            Section("Session") {
                Button("Sign out", role: .destructive) {
                    auth.signOut()
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func roleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        role: UserProfile.ActiveProfile
    ) -> some View {
        let selected = auth.activeProfile == role
        Button {
            Task {
                await auth.switchActiveProfile(role)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(selected ? AppTheme.accent : .secondary)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                            .font(.body.weight(.semibold))
                    }
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AppTheme.accent.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? AppTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
