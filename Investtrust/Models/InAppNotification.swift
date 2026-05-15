import Foundation

// An alert-style notification shown in the in-app notification centre (bell icon).
// Different from push notifications — these are generated from Firestore events.
struct InAppNotification: Identifiable, Equatable {
    // actionRequired shows a red badge; info is purely informational
    enum Kind: String {
        case actionRequired
        case info
    }

    // Where the app should navigate when the user taps the notification
    enum Route: Equatable {
        case dashboard
        case actionExplore
        case actionMyRequests
        case actionOngoing
        case actionCompleted
        case actionSeekerOpportunity
    }

    let id: String
    let title: String
    let message: String
    let createdAt: Date
    let kind: Kind
    let route: Route?   // nil means no navigation, just dismiss
}
