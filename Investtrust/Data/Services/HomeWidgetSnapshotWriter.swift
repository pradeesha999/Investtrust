//
//  HomeWidgetSnapshotWriter.swift
//  Investtrust
//

import Foundation
import WidgetKit

enum HomeWidgetSnapshotWriter {
    private static let upcomingHorizonDays = 400

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

    static func updateActiveProfile(auth: AuthService) {
        guard auth.isSignedIn else { return }
        var snap = HomeWidgetSnapshot.load() ?? .makeEmptySignedIn(activeProfile: auth.activeProfile.rawValue)
        snap.isSignedIn = true
        snap.activeProfile = auth.activeProfile.rawValue
        snap.updatedAt = Date()
        snap.save()
        reloadWidgetTimelines()
    }

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
