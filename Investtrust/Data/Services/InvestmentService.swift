import FirebaseFirestore
import FirebaseStorage
import Foundation
import UIKit
import CryptoKit

final class InvestmentService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let chatService = ChatService()
    private let userService = UserService()

    private static let maxSignatureBytes: Int = 4 * 1024 * 1024
    private static let maxProofBytes: Int = 8 * 1024 * 1024
    private static let overdueGraceDays: Int = 7

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
        case profileIncomplete
        case emptySignature
        case installmentNotFound
        case notLoanOrNoSchedule
        case wrongPartyForInstallmentAction
        case installmentAlreadyComplete
        case missingSignatureImages
        case principalDisbursementNotReady
        case fundingStatusNotAwaitingDisbursement
        case fundingStatusNotDisbursed
        case invalidOfferTerms
        case acceptanceCapacityReached
        case cannotWithdraw
        case agreementUnavailable

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
            case .profileIncomplete:
                return "Complete your profile (legal name, phone, location, bio, and experience) before sending a request."
            case .emptySignature:
                return "Draw your signature before continuing."
            case .installmentNotFound:
                return "That installment was not found."
            case .notLoanOrNoSchedule:
                return "This deal has no loan repayment schedule."
            case .wrongPartyForInstallmentAction:
                return "You’re not allowed to perform this action on this installment."
            case .installmentAlreadyComplete:
                return "This installment is already confirmed."
            case .missingSignatureImages:
                return "Signature images could not be loaded. Please try again or contact support."
            case .principalDisbursementNotReady:
                return "Repayment actions unlock after the principal disbursement is confirmed."
            case .fundingStatusNotAwaitingDisbursement:
                return "This deal is not awaiting principal disbursement."
            case .fundingStatusNotDisbursed:
                return "Principal funding has not been fully confirmed yet."
            case .invalidOfferTerms:
                return "Enter valid offer terms (amount, timeline, and interest rate)."
            case .acceptanceCapacityReached:
                return "Investor capacity is full for this opportunity. Decline older requests or increase max investors."
            case .cannotWithdraw:
                return "Only pending requests can be revoked."
            case .agreementUnavailable:
                return "Memorandum details aren’t available for this request yet."
            }
        }
    }

    /// Investor can revoke only a pending request they created.
    func withdrawInvestmentRequest(investmentId: String, investorId: String) async throws {
        let ref = db.collection("investments").document(investmentId)
        let snap = try await ref.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.investorId == investorId else {
            throw InvestmentServiceError.notSignedIn
        }
        let status = inv.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard status == "pending" else {
            throw InvestmentServiceError.cannotWithdraw
        }
        try await ref.updateData([
            "status": "withdrawn",
            "withdrawnAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
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

    /// Investment rows where this user is the listing owner (`seekerId`), newest first.
    func fetchInvestmentsForSeeker(seekerId: String, limit: Int = 200) async throws -> [InvestmentListing] {
        do {
            let snap = try await db.collection("investments")
                .whereField("seekerId", isEqualTo: seekerId)
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
                .limit(to: max(limit, 120))
                .getDocuments()
        } catch {
            snapshot = try await db.collection("investments").limit(to: 300).getDocuments()
        }
        return snapshot.documents
            .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
            .filter { $0.seekerId == seekerId }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
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
        let cap = max(limit, 25)
        // `whereField + orderBy` needs a composite index in Firestore. Query by investor only, then sort client-side.
        let queryLimit = min(max(cap * 6, 120), 500)

        for investorField in ["investorId", "investor"] {
            do {
                let snapshot = try await db.collection("investments")
                    .whereField(investorField, isEqualTo: userID)
                    .limit(to: queryLimit)
                    .getDocuments()
                let rows = snapshot.documents
                    .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                if !rows.isEmpty {
                    return Array(rows.prefix(cap))
                }
            } catch {
                continue
            }
        }

        do {
            let snapshot = try await db.collection("investments")
                .order(by: "createdAt", descending: true)
                .limit(to: max(cap * 4, 100))
                .getDocuments()
            let rows = snapshot.documents
                .filter { doc in
                    if let investorId = doc.data()["investorId"] as? String { return investorId == userID }
                    if let investorId = doc.data()["investor"] as? String { return investorId == userID }
                    return false
                }
                .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
            return Array(rows.prefix(cap))
        } catch {
            let snapshot = try await db.collection("investments")
                .limit(to: 300)
                .getDocuments()
            let rows = snapshot.documents
                .filter { doc in
                    if let investorId = doc.data()["investorId"] as? String { return investorId == userID }
                    if let investorId = doc.data()["investor"] as? String { return investorId == userID }
                    return false
                }
                .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return Array(rows.prefix(cap))
        }
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
    /// For a single-investor listing, amount is the opportunity’s `amountRequested` unless `proposedAmount` is provided.
    func createInvestmentRequest(
        opportunity: OpportunityListing,
        investorId: String,
        proposedAmount: Double? = nil
    ) async throws -> InvestmentListing {
        guard investorId != opportunity.ownerId else {
            throw InvestmentServiceError.cannotInvestInOwnListing
        }
        let finalAmount: Double = {
            let cap = max(1, opportunity.maximumInvestors ?? 1)
            if cap <= 1 {
                let amt = proposedAmount ?? opportunity.amountRequested
                return amt
            }
            return Self.fixedEqualSplitAmount(total: opportunity.amountRequested, investors: cap)
        }()
        guard finalAmount > 0 else {
            throw InvestmentServiceError.invalidAmount
        }

        if let p = try await userService.fetchProfile(userID: investorId) {
            guard p.profileDetails?.isCompleteForInvesting == true else {
                throw InvestmentServiceError.profileIncomplete
            }
        } else {
            throw InvestmentServiceError.profileIncomplete
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
            "opportunity": [
                "id": opportunity.id,
                "ownerId": opportunity.ownerId
            ] as [String: Any],
            "investorId": investorId,
            "seekerId": opportunity.ownerId,
            "status": "pending",
            "agreementStatus": AgreementStatus.none.rawValue,
            "fundingStatus": FundingStatus.none.rawValue,
            "requestKind": InvestmentRequestKind.default_request.rawValue,
            "offerStatus": InvestmentOfferStatus.pending.rawValue,
            "investmentAmount": finalAmount,
            "finalInterestRate": opportunity.interestRate,
            "finalTimelineMonths": opportunity.repaymentTimelineMonths,
            "investmentType": opportunity.investmentType.rawValue,
            "opportunityInvestmentType": opportunity.investmentType.rawValue,
            "receivedAmount": 0,
            "opportunityTitle": opportunity.title,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now),
            "loanInstallments": []
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

    /// Create/update a pending investment request sourced from a negotiated offer.
    /// For multi-investor opportunities (`maximumInvestors > 1`), amount is always fixed equal split.
    func createOrUpdateOfferRequest(
        opportunity: OpportunityListing,
        investorId: String,
        proposedAmount: Double?,
        proposedInterestRate: Double,
        proposedTimelineMonths: Int,
        description: String,
        source: InvestmentOfferSource,
        chatId: String? = nil,
        chatMessageId: String? = nil
    ) async throws -> InvestmentListing {
        guard investorId != opportunity.ownerId else {
            throw InvestmentServiceError.cannotInvestInOwnListing
        }
        guard proposedInterestRate > 0, proposedTimelineMonths > 0 else {
            throw InvestmentServiceError.invalidOfferTerms
        }
        if let p = try await userService.fetchProfile(userID: investorId) {
            guard p.profileDetails?.isCompleteForInvesting == true else {
                throw InvestmentServiceError.profileIncomplete
            }
        } else {
            throw InvestmentServiceError.profileIncomplete
        }

        let cap = max(1, opportunity.maximumInvestors ?? 1)
        let amount: Double = {
            if cap > 1 {
                return Self.fixedEqualSplitAmount(total: opportunity.amountRequested, investors: cap)
            }
            return proposedAmount ?? 0
        }()
        guard amount > 0 else {
            throw InvestmentServiceError.invalidAmount
        }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        let now = Date()
        var payload: [String: Any] = [
            "opportunityId": opportunity.id,
            "opportunity": [
                "id": opportunity.id,
                "ownerId": opportunity.ownerId
            ] as [String: Any],
            "investorId": investorId,
            "seekerId": opportunity.ownerId,
            "status": "pending",
            "agreementStatus": AgreementStatus.none.rawValue,
            "fundingStatus": FundingStatus.none.rawValue,
            "requestKind": InvestmentRequestKind.offer_request.rawValue,
            "offerStatus": InvestmentOfferStatus.pending.rawValue,
            "offerSource": source.rawValue,
            "offeredAmount": amount,
            "offeredInterestRate": proposedInterestRate,
            "offeredTimelineMonths": proposedTimelineMonths,
            "offerDescription": trimmedDescription,
            "investmentAmount": amount,
            "finalInterestRate": proposedInterestRate,
            "finalTimelineMonths": proposedTimelineMonths,
            "investmentType": opportunity.investmentType.rawValue,
            "opportunityInvestmentType": opportunity.investmentType.rawValue,
            "receivedAmount": 0,
            "opportunityTitle": opportunity.title,
            "updatedAt": Timestamp(date: now),
            "loanInstallments": []
        ]
        if let firstThumb = opportunity.imageStoragePaths.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !firstThumb.isEmpty {
            payload["thumbnailImageURL"] = firstThumb
        }
        if let chatId, !chatId.isEmpty { payload["offerChatId"] = chatId }
        if let chatMessageId, !chatMessageId.isEmpty { payload["offerChatMessageId"] = chatMessageId }

        let ref: DocumentReference
        if let existing = try await fetchLatestRequestForInvestor(opportunityId: opportunity.id, investorId: investorId),
           existing.status.lowercased() == "pending" {
            ref = db.collection("investments").document(existing.id)
            // keep original creation time but mark older offer as superseded semantically
            try await ref.updateData(payload)
        } else {
            ref = db.collection("investments").document()
            payload["createdAt"] = Timestamp(date: now)
            try await ref.setData(payload)
        }

        let snap = try await ref.getDocument()
        guard let merged = snap.data(), let row = InvestmentListing(id: ref.documentID, data: merged) else {
            throw InvestmentServiceError.notFound
        }
        return row
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
        if let cap = opportunity.maximumInvestors, cap > 1 {
            let rows = try await fetchInvestmentsForOpportunity(opportunityId: opportunity.id, limit: 500)
            let occupied = rows.filter { row in
                guard row.id != inv.id else { return false }
                let s = row.status.lowercased()
                if ["accepted", "active", "completed", "defaulted"].contains(s) { return true }
                return row.agreementStatus == .pending_signatures || row.agreementStatus == .active
            }.count
            guard occupied < cap else {
                throw InvestmentServiceError.acceptanceCapacityReached
            }
        }
        let owner = inv.seekerId ?? opportunity.ownerId
        guard owner == seekerId, seekerId == opportunity.ownerId else {
            throw InvestmentServiceError.notOpportunityOwner
        }
        guard let investorId = inv.investorId else {
            throw InvestmentServiceError.missingInvestor
        }

        let now = Date()
        let acceptedInterestRate = inv.offeredInterestRate ?? inv.finalInterestRate ?? opportunity.interestRate
        let acceptedTimelineMonths = inv.offeredTimelineMonths ?? inv.finalTimelineMonths ?? opportunity.repaymentTimelineMonths

        var acceptedUpdates: [String: Any] = [
            "status": "accepted",
            "acceptedAt": Timestamp(date: now),
            "finalInterestRate": acceptedInterestRate,
            "finalTimelineMonths": acceptedTimelineMonths,
            "updatedAt": Timestamp(date: now)
        ]
        if inv.requestKind == .offer_request {
            acceptedUpdates["offerStatus"] = InvestmentOfferStatus.accepted.rawValue
        }
        try await invRef.updateData(acceptedUpdates)
        try await reconcileMasterAgreementForOpportunity(opportunity: opportunity, seekerId: seekerId, now: now)

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

    /// Records signature image (Cloudinary URL in Firestore), and when both parties have signed builds MOA PDF + loan schedule (loans).
    func signAgreement(investmentId: String, userId: String, signaturePNG: Data) async throws {
        guard !signaturePNG.isEmpty, signaturePNG.count <= Self.maxSignatureBytes else {
            throw InvestmentServiceError.emptySignature
        }

        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.agreementStatus == .pending_signatures else {
            throw InvestmentServiceError.agreementNotAwaitingSignatures
        }
        guard let _ = inv.investorId, let _ = inv.seekerId else {
            throw InvestmentServiceError.missingInvestor
        }

        var agreement = inv.agreement
        if agreement == nil, let oid = inv.opportunityId {
            let rows = try await fetchInvestmentsForOpportunity(opportunityId: oid, limit: 500)
            agreement = rows.first(where: { $0.agreement?.agreementId == oid })?.agreement
        }
        guard var agreement else {
            throw InvestmentServiceError.notFound
        }
        guard agreement.requiredSignerIds.contains(userId) else {
            throw InvestmentServiceError.wrongSigner
        }
        guard let signerIndex = agreement.participants.firstIndex(where: { $0.signerId == userId }) else {
            throw InvestmentServiceError.wrongSigner
        }
        let roleKey = agreement.participants[signerIndex].signerRole == .seeker ? "seeker" : "investor"
        let signerAlreadySigned = agreement.participants[signerIndex].isSigned

        // Idempotent retry path: if this signer already signed and both signatures exist,
        // try finalization again instead of failing with "already signed".
        if signerAlreadySigned {
            let signaturesComplete = agreement.participants.allSatisfy(\.isSigned)
            guard signaturesComplete else {
                throw InvestmentServiceError.alreadySigned
            }
            try await finalizeMOAAndLoanSchedule(
                invRef: invRef,
                inv: inv,
                agreement: agreement,
                triggeringUserId: userId
            )
            return
        }

        let uploaded = try await CloudinaryImageUploadClient.uploadImageData(
            signaturePNG,
            filename: "signature-\(investmentId)-\(roleKey).png",
            mimeType: "image/png"
        )

        let now = Date()
        agreement.participants[signerIndex].signedAt = now
        agreement.participants[signerIndex].signatureURL = uploaded.secureURL
        let participantPayload: [[String: Any]] = agreement.participants.map {
            [
                "signerId": $0.signerId,
                "signerRole": $0.signerRole.rawValue,
                "displayName": $0.displayName,
                "signatureURL": $0.signatureURL ?? "",
                "signedAt": ($0.signedAt.map { Timestamp(date: $0) } ?? NSNull()) as Any
            ]
        }

        var updates: [String: Any] = [
            "agreement.participants": participantPayload,
            "agreement.requiredSignerIds": agreement.requiredSignerIds,
            "agreement.termsSnapshotHash": agreement.termsSnapshotHash,
            "updatedAt": Timestamp(date: now)
        ]
        if agreement.participants[signerIndex].signerRole == .seeker {
            updates["signedBySeekerAt"] = Timestamp(date: now)
            updates["seekerSignatureImageURL"] = uploaded.secureURL
            updates["signedBySeekerUserId"] = userId
        } else {
            updates["signedByInvestorAt"] = Timestamp(date: now)
            updates["investorSignatureImageURL"] = uploaded.secureURL
            updates["signedByInvestorUserId"] = userId
        }
        if let opId = inv.opportunityId {
            try await propagateAgreementUpdates(opportunityId: opId, updates: updates)
        } else {
            try await invRef.updateData(updates)
        }

        let mergedSnap = try await invRef.getDocument()
        guard let mergedData = mergedSnap.data(),
              let inv2 = InvestmentListing(id: investmentId, data: mergedData),
              let agreement = inv2.agreement else { return }

        guard agreement.participants.allSatisfy(\.isSigned) else { return }

        try await finalizeMOAAndLoanSchedule(
            invRef: invRef,
            inv: inv2,
            agreement: agreement,
            triggeringUserId: userId
        )
    }

    /// Builds the memorandum PDF locally (styled layout + embedded signatures when URLs load). Safe for preview before all parties sign.
    func buildMOAPDFDocumentData(for investment: InvestmentListing) async throws -> Data {
        guard let agreement = investment.agreement else {
            throw InvestmentServiceError.agreementUnavailable
        }
        var signaturesBySignerId: [String: UIImage] = [:]
        for signer in agreement.participants {
            guard let url = signer.signatureURL, !url.isEmpty else { continue }
            guard let sigData = try? await Self.downloadSignaturePNGData(from: url),
                  let img = UIImage(data: sigData)
            else { continue }
            signaturesBySignerId[signer.signerId] = img
        }
        return MOAPDFBuilder.buildPDF(agreement: agreement, signaturesBySignerId: signaturesBySignerId)
    }

    private static func downloadSignaturePNGData(from urlString: String) async throws -> Data {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw InvestmentServiceError.missingSignatureImages
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw InvestmentServiceError.missingSignatureImages
        }
        guard !data.isEmpty, data.count <= maxSignatureBytes else {
            throw InvestmentServiceError.missingSignatureImages
        }
        return data
    }

    private func finalizeMOAAndLoanSchedule(
        invRef: DocumentReference,
        inv: InvestmentListing,
        agreement: InvestmentAgreementSnapshot,
        triggeringUserId: String
    ) async throws {
        let opportunityId = inv.opportunityId ?? agreement.agreementId
        let linkedRows: [InvestmentListing]
        if !opportunityId.isEmpty {
            let all = try await fetchInvestmentsForOpportunity(opportunityId: opportunityId, limit: 500)
            linkedRows = all.filter { row in
                let s = row.status.lowercased()
                return s == "accepted" || s == "active" || s == "completed" || row.agreementStatus == .pending_signatures || row.agreementStatus == .active
            }
        } else {
            linkedRows = [inv]
        }

        var signaturesBySignerId: [String: UIImage] = [:]
        for signer in agreement.participants {
            guard let url = signer.signatureURL, !url.isEmpty else {
                throw InvestmentServiceError.missingSignatureImages
            }
            let sigData = try await Self.downloadSignaturePNGData(from: url)
            guard let sigImage = UIImage(data: sigData) else {
                throw InvestmentServiceError.missingSignatureImages
            }
            signaturesBySignerId[signer.signerId] = sigImage
        }

        let pdfData = MOAPDFBuilder.buildPDF(
            agreement: agreement,
            signaturesBySignerId: signaturesBySignerId
        )
        let hash = MOAPDFBuilder.sha256Hex(of: pdfData)
        var uploadedPDFURL: String?
        var moaUploadErrorMessage: String?
        do {
            let uploadedPDF = try await CloudinaryImageUploadClient.uploadFileData(
                pdfData,
                filename: "moa-\(agreement.agreementId).pdf",
                mimeType: "application/pdf"
            )
            uploadedPDFURL = uploadedPDF.secureURL
        } catch {
            // Do not block agreement activation when file-host upload fails.
            moaUploadErrorMessage = (error as NSError).localizedDescription
        }

        let now = Date()
        var updates: [String: Any] = [
            "agreementStatus": AgreementStatus.active.rawValue,
            "status": "active",
            "moaContentHash": hash,
            "updatedAt": Timestamp(date: now)
        ]
        if let uploadedPDFURL, !uploadedPDFURL.isEmpty {
            updates["moaPdfURL"] = uploadedPDFURL
            updates["moaUploadError"] = FieldValue.delete()
        } else if let moaUploadErrorMessage, !moaUploadErrorMessage.isEmpty {
            updates["moaUploadError"] = moaUploadErrorMessage
        }

        for row in linkedRows {
            var rowUpdates = updates
            var loanScheduleForCalendar: [LoanInstallment]?
            if row.investmentType == .loan {
                rowUpdates["fundingStatus"] = FundingStatus.awaiting_disbursement.rawValue
                rowUpdates["principalSentByInvestorAt"] = FieldValue.delete()
                rowUpdates["principalReceivedBySeekerAt"] = FieldValue.delete()
                let months = max(1, row.finalTimelineMonths ?? agreement.termsSnapshot.repaymentTimelineMonths ?? 1)
                let rate = row.finalInterestRate ?? agreement.termsSnapshot.interestRate ?? 0
                let plan = agreement.loanRepaymentPlan
                let start = row.acceptedAt ?? now
                let schedule = LoanScheduleGenerator.generateSchedule(
                    principal: row.investmentAmount,
                    annualRatePercent: rate,
                    termMonths: months,
                    plan: plan,
                    startDate: start
                )
                loanScheduleForCalendar = schedule
                rowUpdates["loanInstallments"] = schedule.map { $0.firestoreMap() }
            }
            try await db.collection("investments").document(row.id).updateData(rowUpdates)

            if let schedule = loanScheduleForCalendar {
                let title = row.opportunityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? agreement.opportunityTitle
                    : row.opportunityTitle
                let rowId = row.id
                let investor = row.investorId
                let seeker = row.seekerId
                let uid = triggeringUserId
                Task { @MainActor in
                    await LoanRepaymentCalendarSync.replaceInstallmentReminders(
                        investmentId: rowId,
                        opportunityTitle: title,
                        installments: schedule,
                        actingUserId: uid,
                        investorId: investor,
                        seekerId: seeker
                    )
                }
            }
        }

        if let opId = inv.opportunityId {
            for row in linkedRows {
                guard let investorId = row.investorId, let seekerUid = row.seekerId else { continue }
                let chatId = try await chatService.getOrCreateChat(
                    opportunityId: opId,
                    seekerId: seekerUid,
                    investorId: investorId,
                    opportunityTitle: row.opportunityTitle
                )
                try await chatService.sendMessage(
                    chatId: chatId,
                    senderId: seekerUid,
                    text: "Agreement fully signed by all required parties. MOA PDF is available on the investment record. Proceed with funding."
                )
            }
        }
    }

    // MARK: - Loan installments

    /// Investor marks that the principal has been sent after agreement activation.
    func markPrincipalSentByInvestor(investmentId: String, userId: String) async throws {
        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.investmentType == .loan else {
            throw InvestmentServiceError.notLoanOrNoSchedule
        }
        guard inv.agreementStatus == .active else {
            throw InvestmentServiceError.principalDisbursementNotReady
        }
        guard userId == inv.investorId else {
            throw InvestmentServiceError.wrongPartyForInstallmentAction
        }
        guard inv.fundingStatus == .awaiting_disbursement else {
            throw InvestmentServiceError.fundingStatusNotAwaitingDisbursement
        }

        let now = Date()
        try await invRef.updateData([
            "principalSentByInvestorAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ])
    }

    /// Seeker confirms principal receipt; this unlocks loan installment actions.
    func confirmPrincipalReceivedBySeeker(investmentId: String, userId: String) async throws {
        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.investmentType == .loan else {
            throw InvestmentServiceError.notLoanOrNoSchedule
        }
        guard userId == inv.seekerId else {
            throw InvestmentServiceError.wrongPartyForInstallmentAction
        }
        guard inv.fundingStatus == .awaiting_disbursement else {
            throw InvestmentServiceError.fundingStatusNotAwaitingDisbursement
        }
        guard inv.principalSentByInvestorAt != nil else {
            throw InvestmentServiceError.fundingStatusNotDisbursed
        }

        let now = Date()
        try await invRef.updateData([
            "fundingStatus": FundingStatus.disbursed.rawValue,
            "principalReceivedBySeekerAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ])
    }

    /// Investor marks that they sent payment for an installment (dual-confirmation).
    func markLoanInstallmentPaidByInvestor(investmentId: String, installmentNo: Int, userId: String) async throws {
        try await mutateLoanInstallment(investmentId: investmentId, installmentNo: installmentNo, userId: userId) { row, inv in
            guard userId == inv.investorId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            var next = row
            next.investorMarkedPaidAt = Date()
            if next.seekerMarkedReceivedAt != nil {
                next.status = .confirmed_paid
            } else {
                next.status = .awaiting_confirmation
            }
            return next
        }
    }

    /// Seeker marks that they received payment for an installment (dual-confirmation).
    func markLoanInstallmentReceivedBySeeker(investmentId: String, installmentNo: Int, userId: String) async throws {
        try await mutateLoanInstallment(investmentId: investmentId, installmentNo: installmentNo, userId: userId) { row, inv in
            guard userId == inv.seekerId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            var next = row
            next.seekerMarkedReceivedAt = Date()
            if next.investorMarkedPaidAt != nil {
                next.status = .confirmed_paid
            } else {
                next.status = .awaiting_confirmation
            }
            return next
        }
    }

    /// Upload payment proof image for an installment (Cloudinary URL in Firestore); same JPEG pipeline as opportunity photos.
    func attachLoanInstallmentProof(
        investmentId: String,
        installmentNo: Int,
        userId: String,
        imageJPEG: Data
    ) async throws {
        let payload = ImageJPEGUploadPayload.jpegForUpload(from: imageJPEG)
        guard !payload.isEmpty else {
            throw NSError(domain: "Investtrust", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not read this image. Try another photo or take a new picture."])
        }
        guard payload.count <= Self.maxProofBytes else {
            throw NSError(domain: "Investtrust", code: 400, userInfo: [NSLocalizedDescriptionKey: "Image is too large."])
        }
        try await InappropriateImageGate.validateImageDataForUpload(payload)

        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.investmentType == .loan, !inv.loanInstallments.isEmpty else {
            throw InvestmentServiceError.notLoanOrNoSchedule
        }
        guard inv.fundingStatus == .disbursed else {
            throw InvestmentServiceError.principalDisbursementNotReady
        }
        guard userId == inv.investorId || userId == inv.seekerId else {
            throw InvestmentServiceError.wrongPartyForInstallmentAction
        }

        var rows = inv.loanInstallments.sorted { $0.installmentNo < $1.installmentNo }
        guard let idx = rows.firstIndex(where: { $0.installmentNo == installmentNo }) else {
            throw InvestmentServiceError.installmentNotFound
        }

        let filename = "proof-\(investmentId)-\(installmentNo)-\(UUID().uuidString.prefix(8)).jpg"
        let asset = try await CloudinaryImageUploadClient.uploadImageData(payload, filename: filename)
        let url = asset.secureURL

        var row = rows[idx]
        var proofs = row.proofImageURLs
        proofs.append(url)
        row.proofImageURLs = proofs
        rows[idx] = row

        let receivedTotal = Self.sumConfirmedReceived(rows: rows)
        let updates: [String: Any] = [
            "loanInstallments": rows.map { $0.firestoreMap() },
            "receivedAmount": receivedTotal,
            "updatedAt": Timestamp(date: Date())
        ]
        try await invRef.updateData(updates)
    }

    private func mutateLoanInstallment(
        investmentId: String,
        installmentNo: Int,
        userId: String,
        transform: (LoanInstallment, InvestmentListing) throws -> LoanInstallment
    ) async throws {
        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.investmentType == .loan, !inv.loanInstallments.isEmpty else {
            throw InvestmentServiceError.notLoanOrNoSchedule
        }
        guard inv.fundingStatus == .disbursed else {
            throw InvestmentServiceError.principalDisbursementNotReady
        }
        var rows = inv.loanInstallments.sorted { $0.installmentNo < $1.installmentNo }
        guard let idx = rows.firstIndex(where: { $0.installmentNo == installmentNo }) else {
            throw InvestmentServiceError.installmentNotFound
        }
        let updated = try transform(rows[idx], inv)
        rows[idx] = updated

        let receivedTotal = Self.sumConfirmedReceived(rows: rows)
        var updates: [String: Any] = [
            "loanInstallments": rows.map { $0.firestoreMap() },
            "receivedAmount": receivedTotal,
            "updatedAt": Timestamp(date: Date())
        ]
        if rows.allSatisfy({ $0.status == .confirmed_paid }) {
            updates["status"] = "completed"
            updates["fundingStatus"] = FundingStatus.closed.rawValue
        } else {
            let nextFundingStatus = Self.computeFundingStatus(
                previous: inv.fundingStatus,
                rows: rows,
                now: Date()
            )
            if nextFundingStatus != inv.fundingStatus {
                updates["fundingStatus"] = nextFundingStatus.rawValue
                if nextFundingStatus == .defaulted {
                    updates["status"] = "defaulted"
                }
            }
        }
        try await invRef.updateData(updates)
    }

    private static func sumConfirmedReceived(rows: [LoanInstallment]) -> Double {
        rows.filter { $0.status == .confirmed_paid }.reduce(0) { $0 + $1.totalDue }
    }

    private static func computeFundingStatus(previous: FundingStatus, rows: [LoanInstallment], now: Date) -> FundingStatus {
        if rows.isEmpty { return previous }
        if rows.allSatisfy({ $0.status == .confirmed_paid }) { return .closed }
        guard previous == .disbursed else { return previous }

        let cal = Calendar.current
        let graceBoundary = cal.date(byAdding: .day, value: -overdueGraceDays, to: now) ?? now
        let hasDefaultedInstallment = rows.contains { row in
            row.status != .confirmed_paid && row.dueDate < graceBoundary
        }
        return hasDefaultedInstallment ? .defaulted : previous
    }

    private func propagateAgreementUpdates(opportunityId: String, updates: [String: Any]) async throws {
        let rows = try await fetchInvestmentsForOpportunity(opportunityId: opportunityId, limit: 500)
        let linked = rows.filter { row in
            let s = row.status.lowercased()
            return s == "accepted" || s == "active" || s == "completed" || row.agreementStatus == .pending_signatures || row.agreementStatus == .active
        }
        for row in linked {
            try await db.collection("investments").document(row.id).updateData(updates)
        }
    }

    private func reconcileMasterAgreementForOpportunity(opportunity: OpportunityListing, seekerId: String, now: Date) async throws {
        let rows = try await fetchInvestmentsForOpportunity(opportunityId: opportunity.id, limit: 500)
        let activeRows = rows.filter { row in
            let s = row.status.lowercased()
            return s == "accepted" || s == "active" || s == "completed" || row.agreementStatus == .pending_signatures || row.agreementStatus == .active
        }
        guard !activeRows.isEmpty else { return }

        let existingAgreement = activeRows.compactMap(\.agreement).first
        let hasSignatureStarted = existingAgreement?.participants.contains(where: \.isSigned) == true
        if hasSignatureStarted { return }

        let seekerDisplay = await Self.displayName(userService: userService, userId: seekerId, fallback: "Seeker")
        var participants: [AgreementSignerSnapshot] = [
            AgreementSignerSnapshot(
                signerId: seekerId,
                signerRole: .seeker,
                displayName: seekerDisplay,
                signatureURL: nil,
                signedAt: nil
            )
        ]

        for row in activeRows {
            guard let investorId = row.investorId else { continue }
            if participants.contains(where: { $0.signerId == investorId }) { continue }
            let investorDisplay = await Self.investorLegalOrDisplayName(userService: userService, userId: investorId, fallback: "Investor")
            participants.append(
                AgreementSignerSnapshot(
                    signerId: investorId,
                    signerRole: .investor,
                    displayName: investorDisplay,
                    signatureURL: nil,
                    signedAt: nil
                )
            )
        }

        let requiredSignerIds = participants.map(\.signerId)
        let representativeInvestor = participants.first(where: { $0.signerRole == .investor })?.displayName ?? "Investor"
        let maxAmount = activeRows.map(\.investmentAmount).max() ?? opportunity.amountRequested
        let agreementPayload = Self.makeAgreementPayload(
            opportunity: opportunity,
            agreementId: opportunity.id,
            requiredSignerIds: requiredSignerIds,
            participants: participants,
            investorName: representativeInvestor,
            seekerName: seekerDisplay,
            investmentAmount: maxAmount,
            at: now
        )

        for row in activeRows {
            try await db.collection("investments").document(row.id).updateData([
                "agreementStatus": AgreementStatus.pending_signatures.rawValue,
                "agreementGeneratedAt": Timestamp(date: now),
                "agreement": agreementPayload,
                "updatedAt": Timestamp(date: now)
            ])
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

    private static func investorLegalOrDisplayName(userService: UserService, userId: String, fallback: String) async -> String {
        guard let p = try? await userService.fetchProfile(userID: userId) else { return fallback }
        if let legal = p.profileDetails?.legalFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !legal.isEmpty {
            return legal
        }
        if let n = p.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return fallback
    }

    private static func makeAgreementPayload(
        opportunity: OpportunityListing,
        agreementId: String,
        requiredSignerIds: [String],
        participants: [AgreementSignerSnapshot],
        investorName: String,
        seekerName: String,
        investmentAmount: Double,
        at: Date
    ) -> [String: Any] {
        let termsPayload = OpportunityFirestoreCoding.termsDictionary(from: opportunity.terms, type: opportunity.investmentType)
        let termsHash = termsSnapshotDigest(
            opportunityId: opportunity.id,
            investmentType: opportunity.investmentType.rawValue,
            investmentAmount: investmentAmount,
            terms: termsPayload
        )
        let participantMaps: [[String: Any]] = participants.map {
            [
                "signerId": $0.signerId,
                "signerRole": $0.signerRole.rawValue,
                "displayName": $0.displayName,
                "signatureURL": $0.signatureURL ?? "",
                "signedAt": ($0.signedAt.map { Timestamp(date: $0) } ?? NSNull()) as Any
            ]
        }
        return [
            "agreementId": agreementId,
            "agreementVersion": 1,
            "termsSnapshotHash": termsHash,
            "requiredSignerIds": requiredSignerIds,
            "participants": participantMaps,
            "opportunityTitle": opportunity.title,
            "investorName": investorName,
            "seekerName": seekerName,
            "investmentAmount": investmentAmount,
            "investmentType": opportunity.investmentType.rawValue,
            "termsSnapshot": termsPayload,
            "createdAt": Timestamp(date: at)
        ]
    }

    private static func termsSnapshotDigest(
        opportunityId: String,
        investmentType: String,
        investmentAmount: Double,
        terms: [String: Any]
    ) -> String {
        let payload: [String: Any] = [
            "opportunityId": opportunityId,
            "investmentType": investmentType,
            "investmentAmount": investmentAmount,
            "terms": terms
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return ""
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func fixedEqualSplitAmount(total: Double, investors: Int) -> Double {
        guard total > 0, investors > 0 else { return 0 }
        let raw = total / Double(investors)
        return (raw * 100).rounded() / 100
    }
}
