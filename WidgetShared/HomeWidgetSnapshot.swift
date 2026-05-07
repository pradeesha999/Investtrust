//
//  HomeWidgetSnapshot.swift
//  Investtrust
//
//  Shared between the app and the widget extension (App Group + JSON).
//

import Foundation

enum HomeWidgetConstants {
    static let appGroupIdentifier = "group.investtrust.shared"
    static let snapshotKey = "homeWidgetSnapshotV1"
    static let widgetKind = "InvesttrustHomeWidget"
}

/// One upcoming date the user should know about (loan installment, revenue share cadence, etc.).
struct HomeWidgetEvent: Codable, Equatable {
    var date: Date
    var amount: Double
    var title: String
    var isProjected: Bool
}

struct HomeWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    /// Mirrors `UserProfile.ActiveProfile.rawValue`.
    var activeProfile: String
    var isSignedIn: Bool
    var investorEvents: [HomeWidgetEvent]
    var seekerEvents: [HomeWidgetEvent]

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: HomeWidgetConstants.appGroupIdentifier)
    }

    static func load() -> HomeWidgetSnapshot? {
        guard let data = sharedDefaults?.data(forKey: HomeWidgetConstants.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(HomeWidgetSnapshot.self, from: data)
    }

    func save() {
        guard let sharedDefaults = Self.sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(self) {
            sharedDefaults.set(data, forKey: HomeWidgetConstants.snapshotKey)
        }
    }

    static func makeSignedOut() -> HomeWidgetSnapshot {
        HomeWidgetSnapshot(
            updatedAt: Date(),
            activeProfile: "investor",
            isSignedIn: false,
            investorEvents: [],
            seekerEvents: []
        )
    }

    static func makeEmptySignedIn(activeProfile: String) -> HomeWidgetSnapshot {
        HomeWidgetSnapshot(
            updatedAt: Date(),
            activeProfile: activeProfile,
            isSignedIn: true,
            investorEvents: [],
            seekerEvents: []
        )
    }
}
