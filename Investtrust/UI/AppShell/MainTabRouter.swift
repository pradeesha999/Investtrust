import Combine
import SwiftUI

// The four tabs available in the main tab bar
enum AppTab: Hashable {
    case dashboard
    case action
    case chat
    case settings
}

// Carries the chatId and optional inquiry snapshot when navigating directly to a chat room
struct ChatDeepLink: Hashable {
    let chatId: String
    let inquirySnapshot: OpportunityInquirySnapshot?

    init(chatId: String, inquirySnapshot: OpportunityInquirySnapshot? = nil) {
        self.chatId = chatId
        self.inquirySnapshot = inquirySnapshot
    }
}

// Segments shown in the investor Invest tab's segmented control
enum InvestorInvestSegment: String, CaseIterable, Hashable {
    case explore
    case myRequests
    case ongoing
    case completed

    var title: String {
        switch self {
        case .myRequests: return "My requests"
        case .explore: return "Explore"
        case .ongoing: return "Ongoing"
        case .completed: return "Completed"
        }
    }
}

// Segments shown in the seeker Opportunity tab's segmented control
enum SeekerOpportunitySegment: String, CaseIterable, Hashable {
    case open
    case ongoing
    case completed

    var title: String {
        switch self {
        case .open: return "Open"
        case .ongoing: return "Ongoing"
        case .completed: return "Completed"
        }
    }
}

// Coordinates tab selection and opening chats from anywhere in the shell (e.g. Invest tab, opportunity detail).
final class MainTabRouter: ObservableObject {
    @Published var selectedTab: AppTab = .dashboard
    @Published var pendingChatDeepLink: ChatDeepLink?
    // Which segment is shown when the **Invest** tab is selected (investor mode only).
    @Published var investorInvestSegment: InvestorInvestSegment = .myRequests
    // Triggers seeker create wizard presentation from other tabs (e.g. Home CTA).
    @Published var openSeekerCreateWizard: Bool = false
    // Which segment is shown when the **Opportunity** tab is selected (seeker mode only).
    @Published var seekerOpportunitySegment: SeekerOpportunitySegment = .open
}
