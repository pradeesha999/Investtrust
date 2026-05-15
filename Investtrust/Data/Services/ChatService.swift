import FirebaseFirestore
import Foundation

// Manages chat threads and messages stored in Firestore under `chats/{chatId}`.
// Each seeker/investor pair shares one thread regardless of how many opportunities they discuss.
final class ChatService {
    private let db = Firestore.firestore()

    // Returns the existing chat thread for this pair, or creates one if none exists
    func getOrCreateChat(
        opportunityId: String,
        seekerId: String,
        investorId: String,
        opportunityTitle: String
    ) async throws -> String {
        if let existing = try await findExistingPairChatId(seekerId: seekerId, investorId: investorId) {
            try? await cleanupDuplicatePairChats(seekerId: seekerId, investorId: investorId, keepChatId: existing)
            return existing
        }

        let chatId = canonicalChatId(seekerId: seekerId, investorId: investorId)
        let canonicalRef = db.collection("chats").document(chatId)

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
        do {
            try await canonicalRef.setData(payload)
            try? await cleanupDuplicatePairChats(seekerId: seekerId, investorId: investorId, keepChatId: chatId)
            return chatId
        } catch {
            // Fall back to an auto-generated ID when the canonical ID can't be written (legacy deployments)
            let fallbackRef = db.collection("chats").document()
            try await fallbackRef.setData(payload)
            try? await cleanupDuplicatePairChats(seekerId: seekerId, investorId: investorId, keepChatId: fallbackRef.documentID)
            return fallbackRef.documentID
        }
    }

    func fetchThreads(for userId: String) async throws -> [ChatThread] {
        let docs = try await fetchChatDocumentsScoped(to: userId)

        let allThreads = docs
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

    // For resolving the other participant’s profile (name / avatar) in the chat UI.
    func fetchParticipantIds(chatId: String) async throws -> (seekerId: String, investorId: String)? {
        let snap = try await db.collection("chats").document(chatId).getDocument()
        guard let data = snap.data(),
              let seeker = data["seekerId"] as? String,
              let investor = data["investorId"] as? String else {
            return nil
        }
        return (seeker, investor)
    }

    // Same two UIDs as on the chat document, in stable order for rules + `array-contains` queries.
    private func participantIdsForMessages(chatId: String) async throws -> [String] {
        let snap = try await db.collection("chats").document(chatId).getDocument()
        guard snap.exists, let data = snap.data() else {
            throw ChatServiceError.chatNotFound
        }
        if let ids = data["participantIds"] as? [String], ids.count >= 2 {
            return ids
        }
        if let seeker = data["seekerId"] as? String, let investor = data["investorId"] as? String {
            return [seeker, investor]
        }
        throw ChatServiceError.chatMissingParticipants
    }

    func sendMessage(chatId: String, senderId: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let participantIds = try await participantIdsForMessages(chatId: chatId)
        let chatRef = db.collection("chats").document(chatId)
        let msgRef = chatRef.collection("messages").document()

        let batch = db.batch()
        batch.setData(
            [
                "senderId": senderId,
                "text": trimmed,
                "type": "text",
                "participantIds": participantIds,
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

        let participantIds = try await participantIdsForMessages(chatId: chatId)
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
                "participantIds": participantIds,
                "createdAt": Timestamp(date: now)
            ],
            forDocument: inquiryRef
        )
        batch.setData(
            [
                "senderId": senderId,
                "text": trimmed,
                "type": "text",
                "participantIds": participantIds,
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
        let participantIds = try await participantIdsForMessages(chatId: chatId)
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
            "participantIds": participantIds,
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
        let participantIds = try await participantIdsForMessages(chatId: chatId)
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
            "participantIds": participantIds,
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

    // Backward-compatible chat list query.
    // Prefer `participantIds` (current model), then fall back to legacy pair fields.
    private func fetchChatDocumentsScoped(to userId: String) async throws -> [QueryDocumentSnapshot] {
        do {
            let snapshot = try await db.collection("chats")
                .whereField("participantIds", arrayContains: userId)
                .getDocuments()
            return snapshot.documents
        } catch {
            let seekerSnapshot = try await db.collection("chats")
                .whereField("seekerId", isEqualTo: userId)
                .limit(to: 200)
                .getDocuments()
            let investorSnapshot = try await db.collection("chats")
                .whereField("investorId", isEqualTo: userId)
                .limit(to: 200)
                .getDocuments()

            var docsById: [String: QueryDocumentSnapshot] = [:]
            for doc in seekerSnapshot.documents {
                docsById[doc.documentID] = doc
            }
            for doc in investorSnapshot.documents {
                docsById[doc.documentID] = doc
            }
            return Array(docsById.values)
        }
    }

    // Chats for this exact pair using equality on `seekerId` + `investorId` (both orientations).
    // Avoids `participantIds array-contains` queries that can return unrelated docs and fail Firestore rules.
    private func queryChatsForPair(seekerId: String, investorId: String) async throws -> [QueryDocumentSnapshot] {
        let forward = try await db.collection("chats")
            .whereField("seekerId", isEqualTo: seekerId)
            .whereField("investorId", isEqualTo: investorId)
            .limit(to: 80)
            .getDocuments()
        let flipped = try await db.collection("chats")
            .whereField("seekerId", isEqualTo: investorId)
            .whereField("investorId", isEqualTo: seekerId)
            .limit(to: 80)
            .getDocuments()
        var byId: [String: QueryDocumentSnapshot] = [:]
        for d in forward.documents { byId[d.documentID] = d }
        for d in flipped.documents { byId[d.documentID] = d }
        return Array(byId.values)
    }

    // Finds a previously created chat regardless of legacy id format.
    private func findExistingPairChatId(seekerId: String, investorId: String) async throws -> String? {
        let canonicalId = canonicalChatId(seekerId: seekerId, investorId: investorId)
        do {
            let canonicalSnapshot = try await db.collection("chats").document(canonicalId).getDocument()
            if canonicalSnapshot.exists {
                return canonicalId
            }
        } catch {
            // Legacy or unreadable doc at canonical id — continue discovery below.
        }

        func pairMatchDocId(from docs: [QueryDocumentSnapshot]) -> String? {
            docs.first { doc in
                let data = doc.data()
                return (data["seekerId"] as? String) == seekerId
                    && (data["investorId"] as? String) == investorId
            }?.documentID
        }

        let pairDocs = try await queryChatsForPair(seekerId: seekerId, investorId: investorId)
        if let id = pairMatchDocId(from: pairDocs) { return id }

        // Legacy: participantIds without reliable seeker/investor fields (keep narrow queries).
        do {
            let byInvestor = try await db.collection("chats")
                .whereField("participantIds", arrayContains: investorId)
                .limit(to: 200)
                .getDocuments()
            if let id = pairMatchDocId(from: byInvestor.documents) { return id }

            let bySeeker = try await db.collection("chats")
                .whereField("participantIds", arrayContains: seekerId)
                .limit(to: 200)
                .getDocuments()
            if let id = pairMatchDocId(from: bySeeker.documents) { return id }
        } catch {
            // Strict rules may reject broad participantIds-only queries; pair equality path is primary.
        }

        return nil
    }

    // Deletes duplicate chat documents for a seeker/investor pair and keeps one.
    // Note: Firestore subcollection docs are not recursively deleted by this call.
    private func cleanupDuplicatePairChats(seekerId: String, investorId: String, keepChatId: String) async throws {
        let pairDocs = try await queryChatsForPair(seekerId: seekerId, investorId: investorId)
        let duplicates = pairDocs.filter { doc in
            guard doc.documentID != keepChatId else { return false }
            let data = doc.data()
            return (data["seekerId"] as? String) == seekerId
                && (data["investorId"] as? String) == investorId
        }

        guard !duplicates.isEmpty else { return }

        let batch = db.batch()
        for doc in duplicates {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }
}

enum ChatServiceError: LocalizedError {
    case chatNotFound
    case chatMissingParticipants

    var errorDescription: String? {
        switch self {
        case .chatNotFound:
            return "Chat not found."
        case .chatMissingParticipants:
            return "Chat is missing participant information."
        }
    }
}
