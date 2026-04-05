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

/// Coordinates tab selection and opening chats from anywhere in the shell (e.g. Invest tab, opportunity detail).
final class MainTabRouter: ObservableObject {
    @Published var selectedTab: AppTab = .dashboard
    @Published var pendingChatDeepLink: ChatDeepLink?
}
