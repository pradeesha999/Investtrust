import Foundation

struct ChatThread: Identifiable, Equatable {
    let id: String
    let seekerId: String?
    let investorId: String?
    /// Legacy Firestore field (opportunity title); UI prefers counterparty profile.
    let title: String
    let lastMessagePreview: String
    let lastMessageAt: Date?

    func counterpartyId(currentUserId: String?) -> String? {
        guard let currentUserId else { return nil }
        if seekerId == currentUserId { return investorId }
        if investorId == currentUserId { return seekerId }
        return investorId ?? seekerId
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date?
}
