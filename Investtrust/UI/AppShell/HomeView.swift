//
//  HomeView.swift
//  Investtrust
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthService.self) private var auth
    @State private var selectedTab: AppTab = .dashboard
    /// Avoids resetting the selected tab on every `onAppear`; still moves to Dashboard after a new sign-in (`sessionEpoch` bump).
    @State private var lastSyncedSessionEpoch = -1

    enum AppTab {
        case dashboard
        case action
        case chat
        case settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house")
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
        .onAppear {
            auth.acknowledgeSessionReady()
            if auth.sessionEpoch != lastSyncedSessionEpoch {
                lastSyncedSessionEpoch = auth.sessionEpoch
                if auth.sessionEpoch > 0 {
                    selectedTab = .dashboard
                }
            }
        }
        .onChange(of: auth.dashboardNavigationTrigger) { _, _ in
            selectedTab = .dashboard
        }
    }
    
    @ViewBuilder
    private var actionTab: some View {
        if auth.activeProfile == .investor {
            InvestorMarketView()
        } else {
            SeekerDashboardView()
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthService.previewSignedIn)
}

