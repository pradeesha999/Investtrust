//
//  HomeView.swift
//  Investtrust
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthService.self) private var auth
    @StateObject private var tabRouter = MainTabRouter()

    @State private var lastSyncedSessionEpoch = -1

    var body: some View {
        TabView(selection: tabSelection) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.dashboard)

            actionTab
                .tabItem {
                    Label(auth.activeProfile == .investor ? "Invest" : "Create", systemImage: auth.activeProfile == .investor ? "chart.line.uptrend.xyaxis" : "plus.app")
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
        .tint(AuthTheme.primaryPink)
        .environmentObject(tabRouter)
        .onAppear {
            auth.acknowledgeSessionReady()
            if auth.sessionEpoch != lastSyncedSessionEpoch {
                lastSyncedSessionEpoch = auth.sessionEpoch
                if auth.sessionEpoch > 0 {
                    tabRouter.selectedTab = .dashboard
                }
            }
        }
        .onChange(of: auth.dashboardNavigationTrigger) { _, _ in
            tabRouter.selectedTab = .dashboard
        }
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
}

#Preview {
    HomeView()
        .environment(AuthService.previewSignedIn)
}
