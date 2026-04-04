import Foundation

struct ChatThread: Identifiable, Equatable {
    let id: String
    let title: String
    let lastMessagePreview: String
    let lastMessageAt: Date?
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date?
}
