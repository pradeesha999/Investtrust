//
//  HomeView.swift
//  Investtrust
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @StateObject private var tabRouter = MainTabRouter()

    @State private var lastSyncedSessionEpoch = -1
    @State private var notifications: [InAppNotification] = []
    @State private var showNotifications = false
    private let notificationService = InAppNotificationService()

    var body: some View {
        TabView(selection: tabSelection) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.dashboard)

            actionTab
                .tabItem {
                    Label(auth.activeProfile == .investor ? "Invest" : "Opportunity", systemImage: auth.activeProfile == .investor ? "chart.line.uptrend.xyaxis" : "briefcase.fill")
                }
                .tag(AppTab.action)

            ChatListView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(AppTab.chat)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .tint(auth.accentColor)
        .animation(.accessibleEmphasis(reduceMotion: reduceMotion), value: auth.activeProfile)
        .environmentObject(tabRouter)
        .onAppear {
            auth.acknowledgeSessionReady()
            if auth.sessionEpoch != lastSyncedSessionEpoch {
                lastSyncedSessionEpoch = auth.sessionEpoch
                if auth.sessionEpoch > 0 {
                    tabRouter.selectedTab = .dashboard
                }
            }
            Task { await refreshNotifications() }
        }
        .onChange(of: auth.activeProfile) { _, _ in
            Task { await refreshNotifications() }
        }
        .onChange(of: tabRouter.selectedTab) { _, _ in
            Task { await refreshNotifications() }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer(minLength: 0)
                notificationBell
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
        .sheet(isPresented: $showNotifications) {
            InAppNotificationsView(notifications: notifications) {
                await refreshNotifications()
            } onTapNotification: { note in
                handleNotificationTap(note)
            }
        }
        .accessibilityLabel(tabAccessibilitySummary)
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { tabRouter.selectedTab },
            set: { tabRouter.selectedTab = $0 }
        )
    }

    @ViewBuilder
    private var actionTab: some View {
        if auth.activeProfile == .investor {
            InvestorActionTabView()
        } else {
            SeekerDashboardView()
        }
    }

    private var tabAccessibilitySummary: String {
        auth.activeProfile == .investor
            ? "Investor mode. Tabs: Home, Invest, Chat, Settings."
            : "Opportunity builder mode. Tabs: Home, Opportunity, Chat, Settings."
    }

    private var actionableCount: Int {
        notifications.filter { $0.kind == .actionRequired }.count
    }

    private var notificationBell: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                if actionableCount > 0 {
                    Text("\(min(actionableCount, 9))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.red, in: Capsule())
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func refreshNotifications() async {
        guard let userId = auth.currentUserID else {
            await MainActor.run { notifications = [] }
            return
        }
        do {
            let rows = try await notificationService.fetchNotifications(
                userId: userId,
                activeProfile: auth.activeProfile
            )
            await MainActor.run { notifications = rows }
        } catch {
            await MainActor.run { notifications = [] }
        }
    }

    private func handleNotificationTap(_ note: InAppNotification) {
        guard let route = note.route else { return }
        switch route {
        case .dashboard:
            tabRouter.selectedTab = .dashboard
        case .actionExplore:
            tabRouter.selectedTab = .action
            if auth.activeProfile == .investor {
                tabRouter.investorInvestSegment = .explore
            }
        case .actionMyRequests:
            tabRouter.selectedTab = .action
            if auth.activeProfile == .investor {
                tabRouter.investorInvestSegment = .myRequests
            }
        case .actionOngoing:
            tabRouter.selectedTab = .action
            if auth.activeProfile == .investor {
                tabRouter.investorInvestSegment = .ongoing
            }
        case .actionCompleted:
            tabRouter.selectedTab = .action
            if auth.activeProfile == .investor {
                tabRouter.investorInvestSegment = .completed
            }
        case .actionSeekerOpportunity:
            tabRouter.selectedTab = .action
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthService.previewSignedIn)
}
