import Combine
import SwiftUI

/// Tabs in the signed-in shell (`HomeView`).
enum AppTab: Hashable {
    case dashboard
    case action
    case chat
    case settings
}

/// Deep link into a specific chat room on the Chat tab.
struct ChatDeepLink: Hashable {
    let chatId: String
}

/// Sub-page within the investor **Invest** tab (segmented control).
enum InvestorInvestSegment: String, CaseIterable, Hashable {
    case myRequests
    case explore

    var title: String {
        switch self {
        case .myRequests: return "My requests"
        case .explore: return "Explore"
        }
    }
}

/// Coordinates tab selection and opening chats from anywhere in the shell (e.g. Invest tab, opportunity detail).
final class MainTabRouter: ObservableObject {
    @Published var selectedTab: AppTab = .dashboard
    @Published var pendingChatDeepLink: ChatDeepLink?
    /// Which segment is shown when the **Invest** tab is selected (investor mode only).
    @Published var investorInvestSegment: InvestorInvestSegment = .myRequests
}
