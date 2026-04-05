import FirebaseFirestore
import Foundation

/// Firestore: `chats/{chatId}` and `chats/{chatId}/messages/{messageId}`
/// `chatId` is deterministic: `"\(opportunityId)_\(investorId)"` so one thread per investor per listing.
///
/// Deploy rules so only `participantIds` can read/write chat docs and subcollection messages (e.g. `request.auth.uid in resource.data.participantIds`).
final class ChatService {
    private let db = Firestore.firestore()

    /// Creates the chat document if missing. Returns existing id if already present.
    func getOrCreateChat(
        opportunityId: String,
        seekerId: String,
        investorId: String,
        opportunityTitle: String
    ) async throws -> String {
        let chatId = "\(opportunityId)_\(investorId)"
        let ref = db.collection("chats").document(chatId)
        let snapshot = try await ref.getDocument()
        if snapshot.exists {
            return chatId
        }

        let now = Date()
        let payload: [String: Any] = [
            "opportunityId": opportunityId,
            "seekerId": seekerId,
            "investorId": investorId,
            "participantIds": [seekerId, investorId],
            "title": opportunityTitle,
            "lastMessagePreview": "",
            "createdAt": Timestamp(date: now),
            "lastMessageAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]
        try await ref.setData(payload)
        return chatId
    }

    func fetchThreads(for userId: String) async throws -> [ChatThread] {
        let snapshot = try await db.collection("chats")
            .whereField("participantIds", arrayContains: userId)
            .getDocuments()

        return snapshot.documents
            .compactMap { doc -> ChatThread? in
                let data = doc.data()
                return ChatThread(
                    id: doc.documentID,
                    seekerId: data["seekerId"] as? String,
                    investorId: data["investorId"] as? String,
                    title: data["title"] as? String ?? "Chat",
                    lastMessagePreview: data["lastMessagePreview"] as? String ?? "",
                    lastMessageAt: (data["lastMessageAt"] as? Timestamp)?.dateValue()
                )
            }
            .sorted {
                ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast)
            }
    }

    /// For resolving the other participant’s profile (name / avatar) in the chat UI.
    func fetchParticipantIds(chatId: String) async throws -> (seekerId: String, investorId: String)? {
        let snap = try await db.collection("chats").document(chatId).getDocument()
        guard let data = snap.data(),
              let seeker = data["seekerId"] as? String,
              let investor = data["investorId"] as? String else {
            return nil
        }
        return (seeker, investor)
    }

    func sendMessage(chatId: String, senderId: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let chatRef = db.collection("chats").document(chatId)
        let msgRef = chatRef.collection("messages").document()

        let batch = db.batch()
        batch.setData(
            [
                "senderId": senderId,
                "text": trimmed,
                "type": "text",
                "createdAt": Timestamp(date: Date())
            ],
            forDocument: msgRef
        )
        batch.updateData(
            [
                "lastMessageAt": Timestamp(date: Date()),
                "lastMessagePreview": String(trimmed.prefix(120)),
                "updatedAt": Timestamp(date: Date())
            ],
            forDocument: chatRef
        )
        try await batch.commit()
    }
}
