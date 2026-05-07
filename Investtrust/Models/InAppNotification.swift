import Foundation

struct InAppNotification: Identifiable, Equatable {
    enum Kind: String {
        case actionRequired
        case info
    }

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
    let route: Route?
}
