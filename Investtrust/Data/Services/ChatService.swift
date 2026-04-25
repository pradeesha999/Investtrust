import FirebaseFirestore
import Foundation

/// Firestore: `chats/{chatId}` and `chats/{chatId}/messages/{messageId}`
/// Canonical chat id is pair-based so each seeker/investor pair has one thread across opportunities.
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
        if let existing = try await findExistingPairChatId(seekerId: seekerId, investorId: investorId) {
            try await cleanupDuplicatePairChats(seekerId: seekerId, investorId: investorId, keepChatId: existing)
            return existing
        }

        let chatId = canonicalChatId(seekerId: seekerId, investorId: investorId)
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
        try await cleanupDuplicatePairChats(seekerId: seekerId, investorId: investorId, keepChatId: chatId)
        return chatId
    }

    func fetchThreads(for userId: String) async throws -> [ChatThread] {
        let snapshot = try await db.collection("chats")
            .whereField("participantIds", arrayContains: userId)
            .getDocuments()

        let allThreads = snapshot.documents
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

        // Legacy chat ids were opportunity-scoped, which can produce duplicates
        // for the same user pair. Keep the most recent thread per counterparty pair.
        var dedupedByPair: [String: ChatThread] = [:]
        for thread in allThreads {
            guard let seekerId = thread.seekerId, let investorId = thread.investorId else {
                dedupedByPair[thread.id] = thread
                continue
            }
            let key = canonicalChatId(seekerId: seekerId, investorId: investorId)
            if dedupedByPair[key] == nil {
                dedupedByPair[key] = thread
            }
        }

        return dedupedByPair.values.sorted {
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

    func sendOpportunityInquiryAndMessage(
        chatId: String,
        senderId: String,
        snapshot: OpportunityInquirySnapshot,
        text: String
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let chatRef = db.collection("chats").document(chatId)
        let inquiryRef = chatRef.collection("messages").document()
        let textRef = chatRef.collection("messages").document()
        let now = Date()

        let batch = db.batch()
        batch.setData(
            [
                "senderId": senderId,
                "text": "Opportunity inquiry",
                "type": "opportunity_inquiry",
                "opportunityId": snapshot.opportunityId,
                "opportunityTitle": snapshot.title,
                "investmentTypeLabel": snapshot.investmentTypeLabel,
                "fundingGoalText": snapshot.fundingGoalText,
                "minTicketText": snapshot.minTicketText,
                "termsSummary": snapshot.termsSummary,
                "timelineText": snapshot.timelineText,
                "createdAt": Timestamp(date: now)
            ],
            forDocument: inquiryRef
        )
        batch.setData(
            [
                "senderId": senderId,
                "text": trimmed,
                "type": "text",
                "createdAt": Timestamp(date: now.addingTimeInterval(0.001))
            ],
            forDocument: textRef
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

    func sendInvestmentRequestCard(
        chatId: String,
        senderId: String,
        snapshot: InvestmentRequestSnapshot
    ) async throws -> String {
        let chatRef = db.collection("chats").document(chatId)
        let msgRef = chatRef.collection("messages").document()
        let now = Date()
        let payload: [String: Any] = [
            "senderId": senderId,
            "text": "Investment request",
            "type": "investment_request",
            "investmentId": snapshot.investmentId as Any,
            "opportunityId": snapshot.opportunityId,
            "opportunityTitle": snapshot.title,
            "amountText": snapshot.amountText,
            "interestRateText": snapshot.interestRateText,
            "timelineText": snapshot.timelineText,
            "note": snapshot.note,
            "requestKindLabel": snapshot.requestKindLabel,
            "createdAt": Timestamp(date: now)
        ]
        let batch = db.batch()
        batch.setData(payload, forDocument: msgRef)
        batch.updateData(
            [
                "lastMessageAt": Timestamp(date: now),
                "lastMessagePreview": String("Investment request: \(snapshot.title)".prefix(120)),
                "updatedAt": Timestamp(date: now)
            ],
            forDocument: chatRef
        )
        try await batch.commit()
        return msgRef.documentID
    }

    func sendInvestmentOfferCard(
        chatId: String,
        senderId: String,
        snapshot: InvestmentOfferSnapshot
    ) async throws -> String {
        let chatRef = db.collection("chats").document(chatId)
        let msgRef = chatRef.collection("messages").document()
        let now = Date()
        let payload: [String: Any] = [
            "senderId": senderId,
            "text": "Investment offer",
            "type": "investment_offer",
            "investmentId": snapshot.investmentId as Any,
            "opportunityId": snapshot.opportunityId,
            "opportunityTitle": snapshot.title,
            "amountText": snapshot.amountText,
            "interestRateText": snapshot.interestRateText,
            "timelineText": snapshot.timelineText,
            "descriptionText": snapshot.description,
            "isFixedAmount": snapshot.isFixedAmount,
            "createdAt": Timestamp(date: now)
        ]
        let batch = db.batch()
        batch.setData(payload, forDocument: msgRef)
        batch.updateData(
            [
                "lastMessageAt": Timestamp(date: now),
                "lastMessagePreview": String("Investment offer: \(snapshot.title)".prefix(120)),
                "updatedAt": Timestamp(date: now)
            ],
            forDocument: chatRef
        )
        try await batch.commit()
        return msgRef.documentID
    }

    private func canonicalChatId(seekerId: String, investorId: String) -> String {
        let parts = [seekerId, investorId].sorted()
        return "pair_\(parts[0])_\(parts[1])"
    }

    /// Finds a previously created chat regardless of legacy id format.
    private func findExistingPairChatId(seekerId: String, investorId: String) async throws -> String? {
        let canonicalId = canonicalChatId(seekerId: seekerId, investorId: investorId)
        let canonicalSnapshot = try await db.collection("chats").document(canonicalId).getDocument()
        if canonicalSnapshot.exists {
            return canonicalId
        }

        // Avoid composite-index queries here: fetch by one field and filter in memory.
        let snapshot = try await db.collection("chats")
            .whereField("investorId", isEqualTo: investorId)
            .getDocuments()

        let match = snapshot.documents.first { doc in
            let data = doc.data()
            return (data["seekerId"] as? String) == seekerId
        }
        return match?.documentID
    }

    /// Deletes duplicate chat documents for a seeker/investor pair and keeps one.
    /// Note: Firestore subcollection docs are not recursively deleted by this call.
    private func cleanupDuplicatePairChats(seekerId: String, investorId: String, keepChatId: String) async throws {
        let snapshot = try await db.collection("chats")
            .whereField("investorId", isEqualTo: investorId)
            .getDocuments()

        let duplicates = snapshot.documents.filter { doc in
            guard doc.documentID != keepChatId else { return false }
            let data = doc.data()
            return (data["seekerId"] as? String) == seekerId
        }

        guard !duplicates.isEmpty else { return }

        let batch = db.batch()
        for doc in duplicates {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }
}
