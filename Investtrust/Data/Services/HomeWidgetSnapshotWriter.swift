//
//  HomeWidgetSnapshotWriter.swift
//  Investtrust
//

import Foundation
import WidgetKit

// Writes the HomeWidgetSnapshot to the shared App Group and triggers a WidgetKit timeline reload.
// Called from the investor and seeker dashboards whenever fresh deal data is loaded.
enum HomeWidgetSnapshotWriter {
    // How many days ahead to look when picking upcoming payment events for the widget
    private static let upcomingHorizonDays = 400

    // Called after the investor dashboard loads — updates the investor event list on the widget
    static func persistAfterInvestorDashboardLoad(auth: AuthService, investments: [InvestmentListing]) {
        guard auth.isSignedIn, auth.currentUserID != nil else { return }
        var snap = HomeWidgetSnapshot.load() ?? .makeEmptySignedIn(activeProfile: auth.activeProfile.rawValue)
        snap.isSignedIn = true
        snap.activeProfile = auth.activeProfile.rawValue
        snap.investorEvents = widgetEvents(from: investments)
        snap.updatedAt = Date()
        snap.save()
        reloadWidgetTimelines()
    }

    // Called after the seeker home loads — updates the seeker payment event list on the widget
    static func persistAfterSeekerHomeLoad(auth: AuthService, seekerInvestments: [InvestmentListing]) {
        guard auth.isSignedIn, auth.currentUserID != nil else { return }
        var snap = HomeWidgetSnapshot.load() ?? .makeEmptySignedIn(activeProfile: auth.activeProfile.rawValue)
        snap.isSignedIn = true
        snap.activeProfile = auth.activeProfile.rawValue
        snap.seekerEvents = widgetEvents(from: seekerInvestments)
        snap.updatedAt = Date()
        snap.save()
        reloadWidgetTimelines()
    }

    // Updates only the active profile flag on the snapshot (called when the user switches between investor and seeker mode)
    static func updateActiveProfile(auth: AuthService) {
        guard auth.isSignedIn else { return }
        var snap = HomeWidgetSnapshot.load() ?? .makeEmptySignedIn(activeProfile: auth.activeProfile.rawValue)
        snap.isSignedIn = true
        snap.activeProfile = auth.activeProfile.rawValue
        snap.updatedAt = Date()
        snap.save()
        reloadWidgetTimelines()
    }

    // Replaces the snapshot with a signed-out placeholder so the widget shows the sign-in prompt
    static func clearForSignedOut() {
        HomeWidgetSnapshot.makeSignedOut().save()
        reloadWidgetTimelines()
    }

    private static func widgetEvents(from rows: [InvestmentListing]) -> [HomeWidgetEvent] {
        let upcoming = InvestorPortfolioMetrics.upcomingPayments(withinDays: upcomingHorizonDays, rows: rows)
        return upcoming.prefix(5).map {
            HomeWidgetEvent(date: $0.date, amount: $0.amount, title: $0.title, isProjected: $0.isProjected)
        }
    }

    private static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: HomeWidgetConstants.widgetKind)
    }
}
