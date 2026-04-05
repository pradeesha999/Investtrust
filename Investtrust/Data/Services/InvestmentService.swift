import FirebaseFirestore
import Foundation

final class InvestmentService {
    private let db = Firestore.firestore()
    private let chatService = ChatService()
    private let userService = UserService()

    enum InvestmentServiceError: LocalizedError {
        case notSignedIn
        case cannotInvestInOwnListing
        case invalidAmount
        case pendingRequestExists
        case notFound
        case notOpportunityOwner
        case notPending
        case verificationMessageTooShort
        case missingInvestor
        case agreementNotAwaitingSignatures
        case wrongSigner
        case alreadySigned

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Please sign in again."
            case .cannotInvestInOwnListing:
                return "You can’t send a request on your own listing."
            case .invalidAmount:
                return "Enter a valid investment amount."
            case .pendingRequestExists:
                return "You already have a pending or accepted request for this opportunity."
            case .notFound:
                return "Request not found."
            case .notOpportunityOwner:
                return "Only the opportunity owner can respond to this request."
            case .notPending:
                return "This request is no longer pending."
            case .verificationMessageTooShort:
                return "Add a short verification message (at least a few words) before accepting."
            case .missingInvestor:
                return "This request is missing investor information."
            case .agreementNotAwaitingSignatures:
                return "This agreement is not waiting for signatures."
            case .wrongSigner:
                return "Only the investor or seeker on this deal can sign."
            case .alreadySigned:
                return "You have already signed this agreement."
            }
        }
    }

    /// All investment rows for an opportunity (seeker dashboard). Requires `opportunityId` on each document (or nested `opportunity.id`).
    func fetchInvestmentsForOpportunity(opportunityId: String, limit: Int = 100) async throws -> [InvestmentListing] {
        do {
            let snap = try await db.collection("investments")
                .whereField("opportunityId", isEqualTo: opportunityId)
                .limit(to: limit)
                .getDocuments()
            let rows = snap.documents.compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
            if !rows.isEmpty {
                return rows.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            }
        } catch {
            // fall through
        }

        let snapshot: QuerySnapshot
        do {
            snapshot = try await db.collection("investments")
                .order(by: "createdAt", descending: true)
                .limit(to: max(limit, 50))
                .getDocuments()
        } catch {
            snapshot = try await db.collection("investments").limit(to: 200).getDocuments()
        }
        return snapshot.documents
            .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
            .filter { $0.opportunityId == opportunityId }
    }

    /// Marks a request as declined so the seeker can edit/delete the listing once no blocking requests remain.
    func declineInvestmentRequest(investmentId: String, seekerId: String) async throws {
        let invRef = db.collection("investments").document(investmentId)
        let invSnap = try await invRef.getDocument()
        guard let data = invSnap.data() else {
            throw NSError(
                domain: "Investtrust",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Request not found."]
            )
        }
        guard let inv = InvestmentListing(id: investmentId, data: data) else {
            throw NSError(
                domain: "Investtrust",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Request not found."]
            )
        }
        guard let opId = inv.opportunityId else {
            throw NSError(
                domain: "Investtrust",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "This request is missing an opportunity link."]
            )
        }
        let opSnap = try await db.collection("opportunities").document(opId).getDocument()
        guard opSnap.data()?["ownerId"] as? String == seekerId else {
            throw NSError(
                domain: "Investtrust",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Only the opportunity owner can decline this request."]
            )
        }
        if !inv.blocksSeekerFromManagingOpportunity {
            return
        }
        try await invRef.updateData([
            "status": "declined",
            "declinedAt": FieldValue.serverTimestamp(),
            "declinedBy": seekerId
        ])
    }

    func fetchInvestments(forInvestor userID: String, limit: Int = 50) async throws -> [InvestmentListing] {
        // Try a couple of known field-name variants.
        let queries: [(String, String?)] = [
            ("investorId", "createdAt"),
            ("investor", "createdAt")
        ]
        
        for (investorField, orderField) in queries {
            do {
                var q: Query = db.collection("investments").whereField(investorField, isEqualTo: userID)
                if let orderField {
                    q = q.order(by: orderField, descending: true)
                }
                let snapshot = try await q.limit(to: limit).getDocuments()
                let rows = snapshot.documents.compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
                if !rows.isEmpty {
                    return rows
                }
            } catch {
                // ignore and try next variant
            }
        }
        
        // Last resort: fetch recent and filter in memory.
        let snapshot = try await db.collection("investments")
            .order(by: "createdAt", descending: true)
            .limit(to: max(limit, 25))
            .getDocuments()
        
        return snapshot.documents
            .filter { doc in
                if let investorId = doc.data()["investorId"] as? String { return investorId == userID }
                if let investorId = doc.data()["investor"] as? String { return investorId == userID }
                return false
            }
            .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
    }

    /// Latest investment row for this investor + opportunity (any status), newest first.
    func fetchLatestRequestForInvestor(opportunityId: String, investorId: String) async throws -> InvestmentListing? {
        let snapshot = try await db.collection("investments")
            .whereField("opportunityId", isEqualTo: opportunityId)
            .getDocuments()
        let rows = snapshot.documents
            .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
            .filter { $0.investorId == investorId }
        return rows.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.first
    }

    /// Creates a `pending` investment request (denormalized listing snapshot for investor dashboards).
    func createInvestmentRequest(
        opportunity: OpportunityListing,
        investorId: String,
        proposedAmount: Double
    ) async throws -> InvestmentListing {
        guard investorId != opportunity.ownerId else {
            throw InvestmentServiceError.cannotInvestInOwnListing
        }
        guard proposedAmount > 0 else {
            throw InvestmentServiceError.invalidAmount
        }

        if let existing = try await fetchLatestRequestForInvestor(opportunityId: opportunity.id, investorId: investorId) {
            let s = existing.status.lowercased()
            if !["declined", "rejected", "cancelled", "withdrawn"].contains(s) {
                throw InvestmentServiceError.pendingRequestExists
            }
        }

        let ref = db.collection("investments").document()
        let now = Date()
        let firstThumb = opportunity.imageStoragePaths.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [
            "opportunityId": opportunity.id,
            "investorId": investorId,
            "seekerId": opportunity.ownerId,
            "status": "pending",
            "agreementStatus": AgreementStatus.none.rawValue,
            "investmentAmount": proposedAmount,
            "finalInterestRate": opportunity.interestRate,
            "finalTimelineMonths": opportunity.repaymentTimelineMonths,
            "investmentType": opportunity.investmentType.rawValue,
            "opportunityInvestmentType": opportunity.investmentType.rawValue,
            "receivedAmount": 0,
            "opportunityTitle": opportunity.title,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]
        if let firstThumb, !firstThumb.isEmpty {
            payload["thumbnailImageURL"] = firstThumb
        }
        try await ref.setData(payload)
        let snap = try await ref.getDocument()
        guard let merged = snap.data(), let created = InvestmentListing(id: ref.documentID, data: merged) else {
            throw InvestmentServiceError.notFound
        }
        return created
    }

    /// Seeker accepts a pending request: updates Firestore and sends the verification message in the investor thread.
    func acceptInvestmentRequest(
        investmentId: String,
        seekerId: String,
        opportunity: OpportunityListing,
        verificationMessage: String
    ) async throws {
        let trimmed = verificationMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            throw InvestmentServiceError.verificationMessageTooShort
        }

        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.status.lowercased() == "pending" else {
            throw InvestmentServiceError.notPending
        }
        guard inv.opportunityId == opportunity.id else {
            throw InvestmentServiceError.notFound
        }
        let owner = inv.seekerId ?? opportunity.ownerId
        guard owner == seekerId, seekerId == opportunity.ownerId else {
            throw InvestmentServiceError.notOpportunityOwner
        }
        guard let investorId = inv.investorId else {
            throw InvestmentServiceError.missingInvestor
        }

        let now = Date()
        let investorDisplay = await Self.displayName(userService: userService, userId: investorId, fallback: "Investor")
        let seekerDisplay = await Self.displayName(userService: userService, userId: seekerId, fallback: "Seeker")
        let agreementPayload = Self.makeAgreementPayload(
            opportunity: opportunity,
            investorName: investorDisplay,
            seekerName: seekerDisplay,
            investmentAmount: inv.investmentAmount,
            at: now
        )

        try await invRef.updateData([
            "status": "accepted",
            "acceptedAt": Timestamp(date: now),
            "agreementStatus": AgreementStatus.pending_signatures.rawValue,
            "agreementGeneratedAt": Timestamp(date: now),
            "agreement": agreementPayload,
            "updatedAt": Timestamp(date: now)
        ])

        let chatId = try await chatService.getOrCreateChat(
            opportunityId: opportunity.id,
            seekerId: seekerId,
            investorId: investorId,
            opportunityTitle: opportunity.title
        )
        try await chatService.sendMessage(
            chatId: chatId,
            senderId: seekerId,
            text: "Investment accepted. Agreement ready for signing."
        )
        try await chatService.sendMessage(
            chatId: chatId,
            senderId: seekerId,
            text: "Verification (acceptance): \(trimmed)"
        )
    }

    /// Records a timestamp signature for the current user (investor or seeker). Activates the MOA when both are set.
    func signAgreement(investmentId: String, userId: String) async throws {
        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.agreementStatus == .pending_signatures else {
            throw InvestmentServiceError.agreementNotAwaitingSignatures
        }
        guard let investorId = inv.investorId, let seekerUid = inv.seekerId else {
            throw InvestmentServiceError.missingInvestor
        }

        let now = Date()
        var updates: [String: Any] = [
            "updatedAt": Timestamp(date: now)
        ]

        if userId == investorId {
            guard inv.signedByInvestorAt == nil else { throw InvestmentServiceError.alreadySigned }
            updates["signedByInvestorAt"] = Timestamp(date: now)
        } else if userId == seekerUid {
            guard inv.signedBySeekerAt == nil else { throw InvestmentServiceError.alreadySigned }
            updates["signedBySeekerAt"] = Timestamp(date: now)
        } else {
            throw InvestmentServiceError.wrongSigner
        }

        let willInvestorBeSigned = userId == investorId ? now : inv.signedByInvestorAt
        let willSeekerBeSigned = userId == seekerUid ? now : inv.signedBySeekerAt
        if willInvestorBeSigned != nil, willSeekerBeSigned != nil {
            updates["agreementStatus"] = AgreementStatus.active.rawValue
            updates["status"] = "active"
        }

        try await invRef.updateData(updates)

        if willInvestorBeSigned != nil, willSeekerBeSigned != nil,
           let opId = inv.opportunityId {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opId,
                seekerId: seekerUid,
                investorId: investorId,
                opportunityTitle: inv.opportunityTitle
            )
            try await chatService.sendMessage(
                chatId: chatId,
                senderId: userId,
                text: "Agreement fully signed. Proceed with funding."
            )
        }
    }

    private static func displayName(userService: UserService, userId: String, fallback: String) async -> String {
        if let p = try? await userService.fetchProfile(userID: userId),
           let n = p.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !n.isEmpty {
            return n
        }
        return fallback
    }

    private static func makeAgreementPayload(
        opportunity: OpportunityListing,
        investorName: String,
        seekerName: String,
        investmentAmount: Double,
        at: Date
    ) -> [String: Any] {
        [
            "opportunityTitle": opportunity.title,
            "investorName": investorName,
            "seekerName": seekerName,
            "investmentAmount": investmentAmount,
            "investmentType": opportunity.investmentType.rawValue,
            "termsSnapshot": OpportunityFirestoreCoding.termsDictionary(from: opportunity.terms, type: opportunity.investmentType),
            "createdAt": Timestamp(date: at)
        ]
    }
}

