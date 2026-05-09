import SwiftUI

/// List content for Settings, embeddable inside any `NavigationStack` (e.g. tab root or pushed from Home).
struct SettingsContentView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.effectiveReduceMotion) private var effectiveReduceMotion

    @State private var userProfile: UserProfile?
    @State private var activityMetrics: ProfileActivityMetrics?
    @State private var profileSwitchRotationDegrees: Double = 0
    @State private var calendarSyncEnabled = LoanRepaymentCalendarSync.isCalendarSyncEnabled
    @State private var calendarSyncError: String?

    private let userService = UserService()

    var body: some View {
        List {
            Section {
                profileHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Current role colors: Investor uses blue accents, Opportunity builder uses pink accents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                Text(auth.currentUserEmail ?? "No email")
                    .font(.subheadline)

                NavigationLink {
                    ProfileEditView()
                } label: {
                    Label("Your profile", systemImage: "person.crop.circle")
                }
            }

            Section("Preferences") {
                Toggle("Calendar reminders", isOn: $calendarSyncEnabled)
                    .onChange(of: calendarSyncEnabled) { _, enabled in
                        Task { await handleCalendarToggleChange(enabled: enabled) }
                    }

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

                if let calendarSyncError, !calendarSyncError.isEmpty {
                    Text(calendarSyncError)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
                .accessibilityHint("Signs out of Investtrust on this device.")
            }
        }
        .listStyle(.insetGrouped)
        .task(id: auth.currentUserID) {
            await loadProfileData()
        }
        .onChange(of: auth.activeProfile) { _, _ in
            Task { await loadProfileData() }
        }
        .onAppear {
            calendarSyncEnabled = LoanRepaymentCalendarSync.isCalendarSyncEnabled
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                avatarWithBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(activeSinceLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(profileHeaderAccessibilitySummary)

            Spacer(minLength: 8)

            profileSwitchControl
        }
        .padding(.vertical, 4)
    }

    private var profileHeaderAccessibilitySummary: String {
        "\(displayName). \(activeSinceLine). Activity score \(activityBadgeValue)."
    }

    private var avatarWithBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarImage
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.separator).opacity(0.35), lineWidth: 1))

            Text(activityBadgeText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(auth.accentColor, in: Capsule())
                .offset(x: 4, y: 4)
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let urlString = userProfile?.avatarURL,
           let url = URL(string: urlString),
           !urlString.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemFill))
            Image(systemName: "person.fill")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    private var currentRoleTitle: String {
        auth.activeProfile == .investor ? "Investor" : "Opportunity builder"
    }

    private var nextRoleTitle: String {
        auth.activeProfile == .investor ? "Opportunity builder" : "Investor"
    }

    private var profileSwitchControl: some View {
        VStack(spacing: 6) {
            Button {
                toggleActiveProfile()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(auth.accentColor)
                    .rotationEffect(.degrees(profileSwitchRotationDegrees))
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSwitchProfile)
            .opacity(canSwitchProfile ? 1 : 0.4)
            .accessibilityLabel(switchAccessibilityLabel)
            .accessibilityHint("Double tap to switch between Investor and Opportunity builder.")
            .accessibilityAddTraits(.isButton)

            Text(auth.activeProfile == .investor ? "Investor" : "Seeker")
                .font(.caption.weight(.semibold))
                .foregroundStyle(auth.activeProfile == .investor ? Color.red : Color.blue)
        }
    }

    private var canSwitchProfile: Bool {
        auth.roles.investor && auth.roles.seeker
    }

    private var switchAccessibilityLabel: String {
        if !canSwitchProfile {
            return "Profile switch unavailable"
        }
        return auth.activeProfile == .investor
            ? "Switch to opportunity builder"
            : "Switch to investor"
    }

    private var displayName: String {
        if let n = userProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        if let email = auth.currentUserEmail, let at = email.firstIndex(of: "@") {
            return String(email[..<at])
        }
        return "Member"
    }

    private var activeSinceLine: String {
        guard let created = userProfile?.createdAt else {
            return "Investtrust member"
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy MMM"
        return "Active since \(f.string(from: created))"
    }

    /// Short activity code (listings + completed deals), capped at 999 for the badge.
    private var activityBadgeText: String {
        let o = activityMetrics?.opportunitiesCreated ?? 0
        let d = activityMetrics?.dealsCompletedAsInvestor ?? 0
        let total = min(999, o + d)
        return String(format: "%03d", total)
    }

    private var activityBadgeValue: Int {
        let o = activityMetrics?.opportunitiesCreated ?? 0
        let d = activityMetrics?.dealsCompletedAsInvestor ?? 0
        return min(999, o + d)
    }

    private func toggleActiveProfile() {
        guard canSwitchProfile else { return }
        let next: UserProfile.ActiveProfile = auth.activeProfile == .investor ? .seeker : .investor
        Task { @MainActor in
            await auth.switchActiveProfile(next)
            guard auth.activeProfile == next else { return }
            AppHaptics.selection()
            guard !effectiveReduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                profileSwitchRotationDegrees += 360
            }
        }
    }

    private func loadProfileData() async {
        guard let uid = auth.currentUserID else {
            userProfile = nil
            activityMetrics = nil
            return
        }
        async let profileTask = userService.fetchProfile(userID: uid)
        async let metricsTask = userService.fetchProfileActivityMetrics(userID: uid)
        userProfile = try? await profileTask
        activityMetrics = try? await metricsTask
    }

    private func handleCalendarToggleChange(enabled: Bool) async {
        calendarSyncError = nil
        LoanRepaymentCalendarSync.setCalendarSyncEnabled(enabled)
        guard enabled else {
            LoanRepaymentCalendarSync.clearAllReminders()
            return
        }
        let granted = await LoanRepaymentCalendarSync.requestPermissionIfNeeded()
        guard granted else {
            LoanRepaymentCalendarSync.setCalendarSyncEnabled(false)
            calendarSyncEnabled = false
            calendarSyncError = "Calendar access is not available. Enable access from iOS Settings."
            return
        }
    }
}
