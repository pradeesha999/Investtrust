// Shared between the main app and the widget extension via the App Group.
// The app writes this snapshot whenever deal data changes; the widget reads it to render upcoming events.

import Foundation

// App Group and WidgetKit keys — must match in both targets
enum HomeWidgetConstants {
    static let appGroupIdentifier = "group.investtrust.shared"
    static let snapshotKey = "homeWidgetSnapshotV1"
    static let widgetKind = "InvesttrustHomeWidget"
}

// A single upcoming payment or event shown on the widget (e.g. "Installment #3 due")
struct HomeWidgetEvent: Codable, Equatable {
    var date: Date
    var amount: Double
    var title: String
    var isProjected: Bool  // true when the date is estimated, not confirmed
}

// Full data payload written by the app and read by the widget extension
struct HomeWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var activeProfile: String  // "investor" or "seeker" — controls which event list the widget shows
    var isSignedIn: Bool
    var investorEvents: [HomeWidgetEvent]
    var seekerEvents: [HomeWidgetEvent]

    // Reads from the shared App Group UserDefaults that both targets can access
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: HomeWidgetConstants.appGroupIdentifier)
    }

    // Called by the widget extension on each timeline refresh
    static func load() -> HomeWidgetSnapshot? {
        guard let data = sharedDefaults?.data(forKey: HomeWidgetConstants.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(HomeWidgetSnapshot.self, from: data)
    }

    // Called by the app after fetching updated deal data
    func save() {
        guard let sharedDefaults = Self.sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(self) {
            sharedDefaults.set(data, forKey: HomeWidgetConstants.snapshotKey)
        }
    }

    // Written when the user signs out so the widget shows a signed-out placeholder
    static func makeSignedOut() -> HomeWidgetSnapshot {
        HomeWidgetSnapshot(
            updatedAt: Date(),
            activeProfile: "investor",
            isSignedIn: false,
            investorEvents: [],
            seekerEvents: []
        )
    }

    // Written after sign-in before deal data has loaded
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
