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
    private let opportunityService = OpportunityService()

    private static let maxSignatureBytes: Int = 4 * 1024 * 1024
    private static let maxProofBytes: Int = 8 * 1024 * 1024
    private static let overdueGraceDays: Int = 7

    /// Firestore `PERMISSION_DENIED` (rules) — used to fall back when `offers` writes are rejected (e.g. rules not deployed).
    private static func isFirestorePermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "FIRFirestoreErrorDomain", ns.code == 7 { return true }
        if ns.domain.contains("Firestore"), ns.code == 7 { return true }
        return false
    }

    private struct OfferRecord {
        let amount: Double
        let interestRate: Double
        let timelineMonths: Int
    }

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
        case seekerPaymentProofRequired
        case seekerMustConfirmPaymentFirst
        case installmentOutOfOrder
        case principalProofRequiredBeforeSend
        case disputeReasonTooShort
        case revenuePeriodNotFound
        case notRevenueShareOrNoSchedule
        case revenueDeclarationMissing
        case notEquityDeal
        case updateMessageTooShort
        case milestoneTitleMissing
        case principalNotMarkedSentByInvestor
        case principalAlreadyReceivedBySeeker

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
            case .seekerPaymentProofRequired:
                return "Attach at least one payment slip or transfer screenshot before confirming you sent this installment."
            case .seekerMustConfirmPaymentFirst:
                return "Wait until the seeker confirms they sent this payment before you acknowledge receipt."
            case .installmentOutOfOrder:
                return "Complete the currently due installment first before updating a later one."
            case .principalProofRequiredBeforeSend:
                return "Attach principal transfer proof before marking the principal as sent."
            case .disputeReasonTooShort:
                return "Add a short reason before reporting payment not received."
            case .revenuePeriodNotFound:
                return "That revenue-share period was not found."
            case .notRevenueShareOrNoSchedule:
                return "This deal has no revenue-share schedule."
            case .revenueDeclarationMissing:
                return "The seeker must submit period revenue before payment can be confirmed."
            case .notEquityDeal:
                return "This action is only available for equity deals."
            case .updateMessageTooShort:
                return "Write a short update with at least a few words."
            case .milestoneTitleMissing:
                return "Select a milestone before updating its status."
            case .principalNotMarkedSentByInvestor:
                return "The investor has not marked the principal as sent yet."
            case .principalAlreadyReceivedBySeeker:
                return "Principal has already been confirmed as received."
            }
        }
    }

    /// Investor cancels a **pending** request by deleting its Firestore document (seeker UI and counts update immediately after refresh).
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
        try await ref.delete()
        await MainActor.run {
            LoanRepaymentCalendarSync.clearReminders(forInvestmentId: investmentId)
        }
    }

    /// All investment rows for an opportunity (seeker / listing-owner tooling only).
    /// Do **not** call from an investor-facing flow: the query may include other parties’ documents and Firestore will reject the whole query.
    func fetchInvestmentsForOpportunity(opportunityId: String, limit: Int = 100) async throws -> [InvestmentListing] {
        let snap = try await db.collection("investments")
            .whereField("opportunityId", isEqualTo: opportunityId)
            .limit(to: limit)
            .getDocuments(source: .server)
        let rows = snap.documents.compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
        return rows.sorted { $0.recencyDate > $1.recencyDate }
    }

    /// Investment rows where this user is the listing owner (`seekerId`), newest first.
    /// Rows with status `withdrawn` are omitted (revokes now delete the document; this hides any legacy data).
    func fetchInvestmentsForSeeker(seekerId: String, limit: Int = 200) async throws -> [InvestmentListing] {
        let snap = try await db.collection("investments")
            .whereField("seekerId", isEqualTo: seekerId)
            .limit(to: limit)
            .getDocuments()
        let rows = snap.documents
            .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
            .filter { $0.status.lowercased() != "withdrawn" }
        return rows.sorted { $0.recencyDate > $1.recencyDate }
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

        // Only equality-filtered queries — unscoped `orderBy` / `limit` on `investments` fails under strict
        // Firestore rules because the query may return other users' documents (entire query is denied).
        var merged: [InvestmentListing] = []
        for investorField in ["investorId", "investor"] {
            do {
                let snapshot = try await db.collection("investments")
                    .whereField(investorField, isEqualTo: userID)
                    .limit(to: queryLimit)
                    .getDocuments()
                let rows = snapshot.documents.compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
                merged.append(contentsOf: rows)
            } catch {
                continue
            }
        }
        let deduped = Dictionary(grouping: merged, by: \.id).compactMap { $0.value.first }
        let sorted = deduped.sorted { $0.recencyDate > $1.recencyDate }
        return Array(sorted.prefix(cap))
    }

    /// Latest investment row for this investor + opportunity (any status), newest first.
    /// Must filter by investor in the query (not only in memory): otherwise Firestore rejects the read
    /// when another investor’s row exists for the same opportunity.
    func fetchLatestRequestForInvestor(opportunityId: String, investorId: String) async throws -> InvestmentListing? {
        var merged: [InvestmentListing] = []
        for investorField in ["investorId", "investor"] {
            do {
                let snapshot = try await db.collection("investments")
                    .whereField("opportunityId", isEqualTo: opportunityId)
                    .whereField(investorField, isEqualTo: investorId)
                    .limit(to: 40)
                    .getDocuments()
                merged.append(contentsOf: snapshot.documents.compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) })
            } catch {
                continue
            }
        }
        let deduped = Dictionary(grouping: merged, by: \.id).compactMap { $0.value.first }
        return deduped.sorted { $0.recencyDate > $1.recencyDate }.first
    }

    /// Creates a `pending` investment request (denormalized listing snapshot for investor dashboards).
    /// For a single-investor listing, amount is the opportunity’s `amountRequested` unless `proposedAmount` is provided.
    func createInvestmentRequest(
        opportunity: OpportunityListing,
        investorId: String,
        proposedAmount: Double? = nil
    ) async throws -> InvestmentListing {
        guard let opp = try await opportunityService.fetchOpportunity(opportunityId: opportunity.id) else {
            throw InvestmentServiceError.notFound
        }
        guard investorId != opp.ownerId else {
            throw InvestmentServiceError.cannotInvestInOwnListing
        }
        let finalAmount = Self.resolveRequestedTicketAmount(opp: opp, proposedAmount: proposedAmount)
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

        if let existing = try await fetchLatestRequestForInvestor(opportunityId: opp.id, investorId: investorId) {
            let s = existing.status.lowercased()
            if !["declined", "rejected", "cancelled", "withdrawn"].contains(s) {
                throw InvestmentServiceError.pendingRequestExists
            }
        }

        let ref = db.collection("investments").document()
        let now = Date()
        let firstThumb = opp.imageStoragePaths.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [
            "opportunityId": opp.id,
            "opportunity": [
                "id": opp.id,
                "ownerId": opp.ownerId
            ] as [String: Any],
            "investorId": investorId,
            "seekerId": opp.ownerId,
            "status": "pending",
            "agreementStatus": AgreementStatus.none.rawValue,
            "fundingStatus": FundingStatus.none.rawValue,
            "requestKind": InvestmentRequestKind.default_request.rawValue,
            "offerStatus": InvestmentOfferStatus.pending.rawValue,
            "isOfferRequest": false,
            "investmentAmount": finalAmount,
            "finalInterestRate": opp.interestRate,
            "finalTimelineMonths": opp.repaymentTimelineMonths,
            "investmentType": opp.investmentType.rawValue,
            "opportunityInvestmentType": opp.investmentType.rawValue,
            "receivedAmount": 0,
            "opportunityTitle": opp.title,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now),
            "loanInstallments": [],
            "revenueSharePeriods": []
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

    /// Creates a **single** pending `investments` row with the requested economics on the primary fields
    /// `investmentAmount`, `finalInterestRate`, and `finalTimelineMonths` (easy to read in Firebase console).
    ///
    /// - **Negotiated offer** (`listedTermsOnly == false`): also writes `offered*` / `offer` and an `offers/{id}` doc.
    /// - **Listed terms only** (`listedTermsOnly == true`): same primary fields from the opportunity (split ticket when
    ///   `maximumInvestors > 1`), `requestKind` is `default_request`, no separate `offers` row.
    ///
    /// Supersedes any older **pending** rows for this investor/opportunity so the seeker always sees one current row.
    func createOrUpdateOfferRequest(
        opportunity: OpportunityListing,
        investorId: String,
        proposedAmount: Double?,
        proposedInterestRate: Double,
        proposedTimelineMonths: Int,
        description: String,
        source: InvestmentOfferSource,
        chatId: String? = nil,
        chatMessageId: String? = nil,
        listedTermsOnly: Bool = false
    ) async throws -> InvestmentListing {
        guard let opp = try await opportunityService.fetchOpportunity(opportunityId: opportunity.id) else {
            throw InvestmentServiceError.notFound
        }
        guard investorId != opp.ownerId else {
            throw InvestmentServiceError.cannotInvestInOwnListing
        }

        let amount = Self.resolveRequestedTicketAmount(
            opp: opp,
            proposedAmount: listedTermsOnly ? nil : proposedAmount
        )
        let resolvedRate = listedTermsOnly ? opp.interestRate : proposedInterestRate
        let resolvedMonths = listedTermsOnly ? max(1, opp.repaymentTimelineMonths) : proposedTimelineMonths

        print("[OFFER] service.createOrUpdateOfferRequest listedOnly=\(listedTermsOnly) opp=\(opp.id) inv=\(investorId) investmentAmount=\(amount) finalRate=\(resolvedRate) finalMonths=\(resolvedMonths)")

        guard resolvedMonths > 0 else {
            throw InvestmentServiceError.invalidOfferTerms
        }
        if opp.investmentType == .loan, resolvedRate <= 0 {
            throw InvestmentServiceError.invalidOfferTerms
        }
        if let p = try await userService.fetchProfile(userID: investorId) {
            guard p.profileDetails?.isCompleteForInvesting == true else {
                throw InvestmentServiceError.profileIncomplete
            }
        } else {
            throw InvestmentServiceError.profileIncomplete
        }

        guard amount > 0 else {
            throw InvestmentServiceError.invalidAmount
        }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        let now = Date()
        // Ensure only one actionable pending row per investor/opportunity.
        // Older pending rows become withdrawn/superseded so seeker sees the actual latest offer.
        let existingRows = try await db.collection("investments")
            .whereField("opportunityId", isEqualTo: opp.id)
            .whereField("investorId", isEqualTo: investorId)
            .limit(to: 80)
            .getDocuments()
        let stalePendingRefs = existingRows.documents.filter { doc in
            let data = doc.data()
            let status = ((data["status"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return status == "pending"
        }.map(\.reference)
        if !stalePendingRefs.isEmpty {
            let staleBatch = db.batch()
            for ref in stalePendingRefs {
                staleBatch.updateData([
                    "status": "withdrawn",
                    "offerStatus": InvestmentOfferStatus.superseded.rawValue,
                    "updatedAt": Timestamp(date: now)
                ], forDocument: ref)
            }
            try await staleBatch.commit()
        }

        var payload: [String: Any] = [
            "opportunityId": opp.id,
            "opportunity": [
                "id": opp.id,
                "ownerId": opp.ownerId
            ] as [String: Any],
            "investorId": investorId,
            "seekerId": opp.ownerId,
            "status": "pending",
            "agreementStatus": AgreementStatus.none.rawValue,
            "fundingStatus": FundingStatus.none.rawValue,
            "offerStatus": InvestmentOfferStatus.pending.rawValue,
            // Primary economics — always what you see in console / seeker UI.
            "investmentAmount": amount,
            "finalInterestRate": resolvedRate,
            "finalTimelineMonths": resolvedMonths,
            "investmentType": opp.investmentType.rawValue,
            "opportunityInvestmentType": opp.investmentType.rawValue,
            "receivedAmount": 0,
            "opportunityTitle": opp.title,
            "updatedAt": Timestamp(date: now),
            "loanInstallments": [],
            "revenueSharePeriods": []
        ]

        if listedTermsOnly {
            payload["requestKind"] = InvestmentRequestKind.default_request.rawValue
            payload["isOfferRequest"] = false
        } else {
            payload["requestKind"] = InvestmentRequestKind.offer_request.rawValue
            payload["isOfferRequest"] = true
            payload["offerSource"] = source.rawValue
            payload["offeredAmount"] = amount
            payload["offeredInterestRate"] = resolvedRate
            payload["offeredTimelineMonths"] = resolvedMonths
            payload["offerDescription"] = trimmedDescription
            payload["offer"] = [
                "isOffer": true,
                "amount": amount,
                "interestRate": resolvedRate,
                "timelineMonths": resolvedMonths,
                "description": trimmedDescription,
                "source": source.rawValue,
                "updatedAt": Timestamp(date: now)
            ] as [String: Any]
        }

        if let firstThumb = opp.imageStoragePaths.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !firstThumb.isEmpty {
            payload["thumbnailImageURL"] = firstThumb
        }
        if !listedTermsOnly {
            if let chatId, !chatId.isEmpty { payload["offerChatId"] = chatId }
            if let chatMessageId, !chatMessageId.isEmpty { payload["offerChatMessageId"] = chatMessageId }
        }

        let ref = db.collection("investments").document()
        payload["createdAt"] = Timestamp(date: now)

        if listedTermsOnly {
            try await ref.setData(payload)
        } else {
            let offerRef = db.collection("offers").document()
            payload["offerRecordId"] = offerRef.documentID
            let offerPayload = FirestoreInvestorOffer.creationPayload(
                investmentId: ref.documentID,
                opportunityId: opp.id,
                investorId: investorId,
                seekerId: opp.ownerId,
                amount: amount,
                interestRate: resolvedRate,
                timelineMonths: resolvedMonths,
                description: trimmedDescription,
                source: source.rawValue,
                status: InvestmentOfferStatus.pending.rawValue,
                now: now
            )
            let batch = db.batch()
            batch.setData(payload, forDocument: ref)
            batch.setData(offerPayload, forDocument: offerRef)
            do {
                try await batch.commit()
            } catch {
                guard Self.isFirestorePermissionDenied(error) else { throw error }
                var fallbackPayload = payload
                fallbackPayload.removeValue(forKey: "offerRecordId")
                print("[OFFER] investment+offer batch denied; saving investment doc only (deploy Firestore rules for `offers`). \(error)")
                try await ref.setData(fallbackPayload)
            }
        }

        var snap = try await ref.getDocument()
        guard let merged = snap.data(), let parsed = InvestmentListing(id: ref.documentID, data: merged) else {
            throw InvestmentServiceError.notFound
        }

        if !listedTermsOnly {
            // Safety: force-write canonical offer + primary fields once if decode/cache missed anything.
            if !parsed.isOfferRequest
                || parsed.offeredAmount == nil
                || parsed.offeredInterestRate == nil
                || parsed.offeredTimelineMonths == nil
                || abs(parsed.investmentAmount - amount) > 0.01 {
                try await ref.updateData([
                    "requestKind": InvestmentRequestKind.offer_request.rawValue,
                    "offerStatus": InvestmentOfferStatus.pending.rawValue,
                    "isOfferRequest": true,
                    "offerSource": source.rawValue,
                    "offeredAmount": amount,
                    "offeredInterestRate": resolvedRate,
                    "offeredTimelineMonths": resolvedMonths,
                    "offerDescription": trimmedDescription,
                    "offer": [
                        "isOffer": true,
                        "amount": amount,
                        "interestRate": resolvedRate,
                        "timelineMonths": resolvedMonths,
                        "description": trimmedDescription,
                        "source": source.rawValue,
                        "updatedAt": Timestamp(date: now)
                    ] as [String: Any],
                    "investmentAmount": amount,
                    "finalInterestRate": resolvedRate,
                    "finalTimelineMonths": resolvedMonths,
                    "updatedAt": Timestamp(date: now)
                ])
                snap = try await ref.getDocument()
            }
        }

        guard let finalData = snap.data(), let row = InvestmentListing(id: ref.documentID, data: finalData) else {
            throw InvestmentServiceError.notFound
        }
        print("[OFFER] service wrote id=\(ref.documentID) kind=\(row.requestKind.rawValue) investmentAmount=\(row.investmentAmount) finalRate=\(row.finalInterestRate ?? -1) months=\(row.finalTimelineMonths ?? -1)")
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

        guard let serverOpportunity = try await opportunityService.fetchOpportunity(opportunityId: opportunity.id) else {
            throw InvestmentServiceError.notFound
        }
        guard serverOpportunity.ownerId == seekerId else {
            throw InvestmentServiceError.notOpportunityOwner
        }

        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.status.lowercased() == "pending" else {
            throw InvestmentServiceError.notPending
        }
        guard inv.opportunityId == serverOpportunity.id else {
            throw InvestmentServiceError.notFound
        }
        if let cap = serverOpportunity.maximumInvestors, cap > 1 {
            let rows = try await fetchInvestmentsForOpportunity(opportunityId: serverOpportunity.id, limit: 500)
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
        let owner = inv.seekerId ?? serverOpportunity.ownerId
        guard owner == seekerId else {
            throw InvestmentServiceError.notOpportunityOwner
        }
        guard let investorId = inv.investorId else {
            throw InvestmentServiceError.missingInvestor
        }

        let now = Date()
        let canonicalOffer = try? await fetchLatestOfferRecord(
            investmentId: inv.id,
            opportunityId: serverOpportunity.id,
            seekerUid: seekerId
        )
        let acceptedAmount = canonicalOffer?.amount ?? inv.offeredAmount ?? inv.investmentAmount
        let acceptedInterestRate = canonicalOffer?.interestRate ?? inv.offeredInterestRate ?? inv.finalInterestRate ?? serverOpportunity.interestRate
        let acceptedTimelineMonths = canonicalOffer?.timelineMonths ?? inv.offeredTimelineMonths ?? inv.finalTimelineMonths ?? serverOpportunity.repaymentTimelineMonths

        var acceptedUpdates: [String: Any] = [
            "status": "accepted",
            "acceptedAt": Timestamp(date: now),
            "investmentAmount": acceptedAmount,
            "offeredAmount": acceptedAmount,
            "finalInterestRate": acceptedInterestRate,
            "offeredInterestRate": acceptedInterestRate,
            "finalTimelineMonths": acceptedTimelineMonths,
            "offeredTimelineMonths": acceptedTimelineMonths,
            "updatedAt": Timestamp(date: now)
        ]
        if inv.requestKind == .offer_request {
            acceptedUpdates["offerStatus"] = InvestmentOfferStatus.accepted.rawValue
        }
        try await invRef.updateData(acceptedUpdates)
        try await opportunityService.applyAcceptedInvestmentTermsToListing(
            opportunity: serverOpportunity,
            ownerId: seekerId,
            acceptedAmount: acceptedAmount,
            acceptedRate: acceptedInterestRate,
            acceptedTimelineMonths: acceptedTimelineMonths
        )
        if inv.requestKind == .offer_request {
            try await markOfferAccepted(investmentId: inv.id, opportunityId: serverOpportunity.id, seekerId: seekerId, at: now)
        }
        try await reconcileMasterAgreementForOpportunity(opportunity: serverOpportunity, seekerId: seekerId, now: now)

        let chatId = try await chatService.getOrCreateChat(
            opportunityId: serverOpportunity.id,
            seekerId: seekerId,
            investorId: investorId,
            opportunityTitle: serverOpportunity.title
        )
        let acceptedAmountText = Self.lkrAmountText(acceptedAmount)
        let acceptedRateText = String(format: "%.2f", acceptedInterestRate)
        let termsLine: String = {
            switch serverOpportunity.investmentType {
            case .loan:
                return "Accepted terms: \(acceptedRateText)% interest · \(acceptedTimelineMonths) months"
            default:
                return "Accepted timeline: \(acceptedTimelineMonths) months"
            }
        }()
        let detailsMessage = """
        Your investment request was accepted for "\(serverOpportunity.title)".
        Category: \(serverOpportunity.category)
        Type: \(serverOpportunity.investmentType.rawValue)
        Accepted amount: LKR \(acceptedAmountText)
        \(termsLine)
        Location: \(serverOpportunity.location)
        Use of funds: \(serverOpportunity.useOfFunds)
        Next step: review and sign the agreement in-app.
        """
        try await chatService.sendMessage(
            chatId: chatId,
            senderId: seekerId,
            text: detailsMessage
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
        // Only the seeker may list all `investments` for an opportunity; investors hit PERMISSION_DENIED.
        if agreement == nil, let oid = inv.opportunityId,
           let seeker = inv.seekerId, userId == seeker {
            let rows = try await fetchInvestmentsForOpportunity(opportunityId: oid, limit: 500)
            agreement = rows.first(where: {
                $0.agreement?.agreementId == oid || $0.id == investmentId
            })?.agreement
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
        let syncIds: [String] = {
            let linked = agreement.linkedInvestmentIds.filter { !$0.isEmpty }
            if !linked.isEmpty { return Array(Set(linked)) }
            return [investmentId]
        }()
        let batch = db.batch()
        for syncId in syncIds {
            batch.updateData(updates, forDocument: db.collection("investments").document(syncId))
        }
        try await batch.commit()

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
        let candidateIds: [String] = {
            let linked = agreement.linkedInvestmentIds.filter { !$0.isEmpty }
            if !linked.isEmpty { return Array(Set(linked)) }
            return [inv.id]
        }()
        var linkedRows: [InvestmentListing] = []
        for docId in candidateIds {
            let snap = try await db.collection("investments").document(docId).getDocument()
            guard let data = snap.data(), let row = InvestmentListing(id: docId, data: data) else { continue }
            let s = row.status.lowercased()
            guard s == "accepted" || s == "active" || s == "completed" || row.agreementStatus == .pending_signatures || row.agreementStatus == .active else { continue }
            linkedRows.append(row)
        }
        if linkedRows.isEmpty {
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

        let opportunityForEquity: OpportunityListing?
        if let opportunityId = inv.opportunityId, !opportunityId.isEmpty {
            opportunityForEquity = try? await opportunityService.fetchOpportunity(opportunityId: opportunityId)
        } else {
            opportunityForEquity = nil
        }
        var finalizeRows: [(row: InvestmentListing, updates: [String: Any], loanSchedule: [LoanInstallment]?)] = []
        finalizeRows.reserveCapacity(linkedRows.count)
        for row in linkedRows {
            var rowUpdates = updates
            var loanScheduleForCalendar: [LoanInstallment]?
            if row.investmentType == .loan {
                rowUpdates["fundingStatus"] = FundingStatus.awaiting_disbursement.rawValue
                rowUpdates["principalSentByInvestorAt"] = FieldValue.delete()
                rowUpdates["principalReceivedBySeekerAt"] = FieldValue.delete()
                rowUpdates["principalInvestorProofImageURLs"] = FieldValue.delete()
                rowUpdates["principalSeekerProofImageURLs"] = FieldValue.delete()
                rowUpdates["principalSeekerNotReceivedAt"] = FieldValue.delete()
                rowUpdates["principalSeekerNotReceivedReason"] = FieldValue.delete()
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
                rowUpdates["revenueSharePeriods"] = []
            } else if row.investmentType == .equity {
                rowUpdates["fundingStatus"] = FundingStatus.disbursed.rawValue
                rowUpdates["loanInstallments"] = []
                rowUpdates["revenueSharePeriods"] = []
                if let opportunityForEquity {
                    rowUpdates["equityMilestones"] = buildInitialEquityMilestonePayload(
                        from: opportunityForEquity.milestones,
                        acceptedAt: row.acceptedAt ?? now
                    )
                } else {
                    rowUpdates["equityMilestones"] = []
                }
                rowUpdates["equityUpdates"] = []
            }
            finalizeRows.append((row, rowUpdates, loanScheduleForCalendar))
        }

        let commitBatch = db.batch()
        for item in finalizeRows {
            commitBatch.updateData(item.updates, forDocument: db.collection("investments").document(item.row.id))
        }
        try await commitBatch.commit()

        // Calendar sync is intentionally deferred until the user re-opens the app/opportunity
        // and explicitly accepts consent, to avoid prompting during signing completion.

        // Rules require `senderId == request.auth.uid`. Finalization may be triggered by seeker or investor.
        // Chat is best-effort: if it fails, investment rows are already committed — don’t surface a false failure.
        if let opId = inv.opportunityId {
            for row in linkedRows {
                guard let investorId = row.investorId, let seekerUid = row.seekerId else { continue }
                do {
                    let chatId = try await chatService.getOrCreateChat(
                        opportunityId: opId,
                        seekerId: seekerUid,
                        investorId: investorId,
                        opportunityTitle: row.opportunityTitle
                    )
                    try await chatService.sendMessage(
                        chatId: chatId,
                        senderId: triggeringUserId,
                        text: "Agreement fully signed by all required parties. MOA PDF is available on the investment record. Proceed with funding."
                    )
                } catch {
                    // Non-fatal: MOA state is already on Firestore.
                }
            }
        }
    }

    // MARK: - Loan installments

    private func buildInitialEquityMilestonePayload(from milestones: [OpportunityMilestone], acceptedAt: Date) -> [[String: Any]] {
        let sorted = OpportunityFirestoreCoding.sortedMilestonesChronologically(milestones)
        return sorted.map { row in
            let dueDate: Date? = {
                if let days = row.dueDaysAfterAcceptance, days >= 0 {
                    return Calendar.current.date(byAdding: .day, value: days, to: acceptedAt)
                }
                return row.expectedDate
            }()
            var payload: [String: Any] = [
                "title": row.title,
                "description": row.description,
                "status": EquityMilestoneStatus.planned.rawValue
            ]
            if let dueDate { payload["dueDate"] = Timestamp(date: dueDate) }
            return payload
        }
    }

    func postEquityVentureUpdate(
        investmentId: String,
        seekerId: String,
        title: String,
        message: String,
        ventureStage: VentureStage?,
        growthMetric: String?,
        attachmentURLs: [String] = []
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanMessage.count >= 8 else { throw InvestmentServiceError.updateMessageTooShort }
        let ref = db.collection("investments").document(investmentId)
        let snap = try await ref.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.investmentType == .equity else { throw InvestmentServiceError.notEquityDeal }
        guard inv.seekerId == seekerId else { throw InvestmentServiceError.notOpportunityOwner }
        guard inv.agreementStatus == .active else { throw InvestmentServiceError.agreementNotAwaitingSignatures }

        let now = Date()
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "title": cleanTitle.isEmpty ? "Venture update" : cleanTitle,
            "message": cleanMessage,
            "ventureStage": ventureStage?.rawValue as Any,
            "growthMetric": growthMetric?.trimmingCharacters(in: .whitespacesAndNewlines) as Any,
            "attachmentURLs": attachmentURLs,
            "createdAt": Timestamp(date: now)
        ]
        try await ref.updateData([
            "equityUpdates": FieldValue.arrayUnion([payload]),
            "updatedAt": Timestamp(date: now)
        ])
    }

    func updateEquityMilestoneStatus(
        investmentId: String,
        seekerId: String,
        milestoneTitle: String,
        status: EquityMilestoneStatus,
        note: String?
    ) async throws {
        let cleanTitle = milestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw InvestmentServiceError.milestoneTitleMissing }
        let ref = db.collection("investments").document(investmentId)
        let snap = try await ref.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard inv.investmentType == .equity else { throw InvestmentServiceError.notEquityDeal }
        guard inv.seekerId == seekerId else { throw InvestmentServiceError.notOpportunityOwner }
        guard inv.agreementStatus == .active else { throw InvestmentServiceError.agreementNotAwaitingSignatures }
        let now = Date()
        let updatedMilestones = inv.equityMilestones.map { row -> [String: Any] in
            let matches = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(cleanTitle) == .orderedSame
            return [
                "title": row.title,
                "description": row.description,
                "dueDate": (row.dueDate.map { Timestamp(date: $0) } ?? NSNull()) as Any,
                "status": (matches ? status : row.status).rawValue,
                "updatedAt": (matches ? Timestamp(date: now) : (row.updatedAt.map { Timestamp(date: $0) } ?? NSNull())) as Any,
                "note": (matches ? note?.trimmingCharacters(in: .whitespacesAndNewlines) : row.note) as Any
            ]
        }
        try await ref.updateData([
            "equityMilestones": updatedMilestones,
            "updatedAt": Timestamp(date: now)
        ])
    }

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
        guard !inv.principalInvestorProofImageURLs.isEmpty else {
            throw InvestmentServiceError.principalProofRequiredBeforeSend
        }

        let now = Date()
        try await invRef.updateData([
            "principalSentByInvestorAt": Timestamp(date: now),
            "principalSeekerNotReceivedAt": FieldValue.delete(),
            "principalSeekerNotReceivedReason": FieldValue.delete(),
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
            "principalSeekerNotReceivedAt": FieldValue.delete(),
            "principalSeekerNotReceivedReason": FieldValue.delete(),
            "updatedAt": Timestamp(date: now)
        ])
    }

    /// Seeker reports that the principal the investor marked as sent was not received. Clears “sent” and proof URLs so the investor can upload fresh proof and mark sent again.
    func reportPrincipalNotReceivedBySeeker(
        investmentId: String,
        userId: String,
        reason: String
    ) async throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            throw InvestmentServiceError.disputeReasonTooShort
        }
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
            throw InvestmentServiceError.principalNotMarkedSentByInvestor
        }
        guard inv.principalReceivedBySeekerAt == nil else {
            throw InvestmentServiceError.principalAlreadyReceivedBySeeker
        }

        let now = Date()
        try await invRef.updateData([
            "principalSentByInvestorAt": FieldValue.delete(),
            "principalInvestorProofImageURLs": [],
            "principalSeekerProofImageURLs": [],
            "principalSeekerNotReceivedAt": Timestamp(date: now),
            "principalSeekerNotReceivedReason": trimmed,
            "updatedAt": Timestamp(date: now)
        ])
    }

    /// Upload proof for initial principal disbursement so both parties can review evidence.
    func attachPrincipalDisbursementProof(investmentId: String, userId: String, imageJPEG: Data) async throws {
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
        guard inv.investmentType == .loan else {
            throw InvestmentServiceError.notLoanOrNoSchedule
        }
        guard inv.agreementStatus == .active else {
            throw InvestmentServiceError.principalDisbursementNotReady
        }
        guard inv.fundingStatus == .awaiting_disbursement || inv.fundingStatus == .disbursed else {
            throw InvestmentServiceError.principalDisbursementNotReady
        }
        guard userId == inv.investorId || userId == inv.seekerId else {
            throw InvestmentServiceError.wrongPartyForInstallmentAction
        }

        let filename = "principal-proof-\(investmentId)-\(UUID().uuidString.prefix(8)).jpg"
        let asset = try await CloudinaryImageUploadClient.uploadImageData(payload, filename: filename)
        let url = asset.secureURL

        var updates: [String: Any] = ["updatedAt": Timestamp(date: Date())]
        if userId == inv.investorId {
            updates["principalInvestorProofImageURLs"] = FieldValue.arrayUnion([url])
        } else {
            updates["principalSeekerProofImageURLs"] = FieldValue.arrayUnion([url])
        }
        try await invRef.updateData(updates)
    }

    /// Investor confirms they **received** this repayment (optionally after uploading receipt proof). Requires seeker to have confirmed payment sent first.
    func markLoanInstallmentPaidByInvestor(investmentId: String, installmentNo: Int, userId: String) async throws {
        try await mutateLoanInstallment(investmentId: investmentId, installmentNo: installmentNo, userId: userId) { row, inv in
            guard userId == inv.investorId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            guard row.seekerMarkedReceivedAt != nil else { throw InvestmentServiceError.seekerMustConfirmPaymentFirst }
            var next = row
            next.investorMarkedPaidAt = Date()
            next.status = .confirmed_paid
            return next
        }
    }

    /// Investor reports this installment as not received and sends a reason back to seeker.
    /// This resets seeker confirmation and seeker proof so seeker must re-upload proof and confirm again.
    func markLoanInstallmentNotReceivedByInvestor(
        investmentId: String,
        installmentNo: Int,
        userId: String,
        reason: String
    ) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReason.count >= 6 else {
            throw InvestmentServiceError.disputeReasonTooShort
        }
        try await mutateLoanInstallment(investmentId: investmentId, installmentNo: installmentNo, userId: userId) { row, inv in
            guard userId == inv.investorId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            guard row.seekerMarkedReceivedAt != nil else { throw InvestmentServiceError.seekerMustConfirmPaymentFirst }
            var next = row
            next.status = .disputed
            next.investorMarkedPaidAt = nil
            next.seekerMarkedReceivedAt = nil
            next.seekerProofImageURLs = []
            next.latestDisputeReason = trimmedReason
            next.latestDisputedAt = Date()
            return next
        }
    }

    /// Seeker confirms they **sent** this installment payment. Requires at least one seeker payment proof image.
    func markLoanInstallmentReceivedBySeeker(investmentId: String, installmentNo: Int, userId: String) async throws {
        try await mutateLoanInstallment(investmentId: investmentId, installmentNo: installmentNo, userId: userId) { row, inv in
            guard userId == inv.seekerId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            guard !row.seekerProofImageURLs.isEmpty else { throw InvestmentServiceError.seekerPaymentProofRequired }
            var next = row
            next.seekerMarkedReceivedAt = Date()
            next.latestDisputeReason = nil
            next.latestDisputedAt = nil
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
        guard Self.isInstallmentActionOrderValid(installmentNo: installmentNo, rows: rows) else {
            throw InvestmentServiceError.installmentOutOfOrder
        }

        var row = rows[idx]
        if userId == inv.investorId {
            guard row.seekerMarkedReceivedAt != nil else {
                throw InvestmentServiceError.seekerMustConfirmPaymentFirst
            }
        }

        let filename = "proof-\(investmentId)-\(installmentNo)-\(UUID().uuidString.prefix(8)).jpg"
        let asset = try await CloudinaryImageUploadClient.uploadImageData(payload, filename: filename)
        let url = asset.secureURL

        if userId == inv.seekerId {
            row.seekerProofImageURLs.append(url)
        } else if userId == inv.investorId {
            row.investorProofImageURLs.append(url)
        }
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
        guard Self.isInstallmentActionOrderValid(installmentNo: installmentNo, rows: rows) else {
            throw InvestmentServiceError.installmentOutOfOrder
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

    private static func isInstallmentActionOrderValid(installmentNo: Int, rows: [LoanInstallment]) -> Bool {
        guard let nextOpen = rows.first(where: { $0.status != .confirmed_paid }) else {
            return false
        }
        return nextOpen.installmentNo == installmentNo
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

    // MARK: - Revenue share periods

    func declareRevenueForPeriod(
        investmentId: String,
        periodNo: Int,
        declaredRevenue: Double,
        userId: String
    ) async throws {
        try await mutateRevenueSharePeriod(investmentId: investmentId, periodNo: periodNo, userId: userId) { row, inv, allRows in
            guard userId == inv.seekerId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            guard declaredRevenue >= 0 else { throw InvestmentServiceError.invalidAmount }
            let capAmount = Self.revenueShareCapAmount(for: inv)
            let alreadyPaid = Self.sumConfirmedRevenueSharePaid(rows: allRows)
            let remainingCap = max(0, capAmount - alreadyPaid)
            let sharePct = max(0, inv.agreement?.termsSnapshot.revenueSharePercent ?? 0)
            let calculated = min(remainingCap, (declaredRevenue * sharePct) / 100.0)
            var next = row
            next.declaredRevenue = declaredRevenue
            next.expectedShareAmount = max(0, Self.round2(calculated))
            next.seekerDeclaredAt = Date()
            next.status = .awaiting_payment
            return next
        }
    }

    func markRevenueSharePeriodPaidBySeeker(
        investmentId: String,
        periodNo: Int,
        userId: String
    ) async throws {
        try await mutateRevenueSharePeriod(investmentId: investmentId, periodNo: periodNo, userId: userId) { row, inv, _ in
            guard userId == inv.seekerId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            guard row.declaredRevenue != nil else { throw InvestmentServiceError.revenueDeclarationMissing }
            let due = max(0, row.expectedShareAmount ?? 0)
            if due > 0 {
                guard !row.seekerProofImageURLs.isEmpty || row.investorMarkedReceivedAt != nil else {
                    throw InvestmentServiceError.seekerPaymentProofRequired
                }
            }
            var next = row
            next.seekerMarkedSentAt = Date()
            if next.investorMarkedReceivedAt != nil {
                next.actualPaidAmount = Self.round2(due)
                next.status = .confirmed_paid
            } else {
                next.status = .awaiting_confirmation
            }
            return next
        }
    }

    func markRevenueSharePeriodReceivedByInvestor(
        investmentId: String,
        periodNo: Int,
        userId: String
    ) async throws {
        try await mutateRevenueSharePeriod(investmentId: investmentId, periodNo: periodNo, userId: userId) { row, inv, _ in
            guard userId == inv.investorId else { throw InvestmentServiceError.wrongPartyForInstallmentAction }
            guard row.status != .confirmed_paid else { throw InvestmentServiceError.installmentAlreadyComplete }
            guard row.seekerMarkedSentAt != nil else { throw InvestmentServiceError.seekerMustConfirmPaymentFirst }
            guard row.declaredRevenue != nil else { throw InvestmentServiceError.revenueDeclarationMissing }
            var next = row
            next.investorMarkedReceivedAt = Date()
            next.actualPaidAmount = Self.round2(max(0, next.expectedShareAmount ?? 0))
            next.status = .confirmed_paid
            return next
        }
    }

    func attachRevenueSharePeriodProof(
        investmentId: String,
        periodNo: Int,
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
        guard !inv.revenueSharePeriods.isEmpty else {
            throw InvestmentServiceError.notRevenueShareOrNoSchedule
        }
        guard inv.fundingStatus == .disbursed else {
            throw InvestmentServiceError.principalDisbursementNotReady
        }
        guard userId == inv.investorId || userId == inv.seekerId else {
            throw InvestmentServiceError.wrongPartyForInstallmentAction
        }

        var rows = inv.revenueSharePeriods.sorted { $0.periodNo < $1.periodNo }
        guard let idx = rows.firstIndex(where: { $0.periodNo == periodNo }) else {
            throw InvestmentServiceError.revenuePeriodNotFound
        }
        let filename = "revproof-\(investmentId)-\(periodNo)-\(UUID().uuidString.prefix(8)).jpg"
        let asset = try await CloudinaryImageUploadClient.uploadImageData(payload, filename: filename)
        let url = asset.secureURL

        var row = rows[idx]
        if userId == inv.seekerId {
            row.seekerProofImageURLs.append(url)
        } else {
            row.investorProofImageURLs.append(url)
        }
        rows[idx] = row

        let paid = Self.sumConfirmedRevenueSharePaid(rows: rows)
        let updates: [String: Any] = [
            "revenueSharePeriods": rows.map { $0.firestoreMap() },
            "receivedAmount": paid,
            "updatedAt": Timestamp(date: Date())
        ]
        try await invRef.updateData(updates)
    }

    private func mutateRevenueSharePeriod(
        investmentId: String,
        periodNo: Int,
        userId: String,
        transform: (RevenueSharePeriod, InvestmentListing, [RevenueSharePeriod]) throws -> RevenueSharePeriod
    ) async throws {
        let invRef = db.collection("investments").document(investmentId)
        let snap = try await invRef.getDocument()
        guard let data = snap.data(), let inv = InvestmentListing(id: investmentId, data: data) else {
            throw InvestmentServiceError.notFound
        }
        guard !inv.revenueSharePeriods.isEmpty else {
            throw InvestmentServiceError.notRevenueShareOrNoSchedule
        }
        guard inv.fundingStatus == .disbursed else {
            throw InvestmentServiceError.principalDisbursementNotReady
        }
        var rows = inv.revenueSharePeriods.sorted { $0.periodNo < $1.periodNo }
        guard let idx = rows.firstIndex(where: { $0.periodNo == periodNo }) else {
            throw InvestmentServiceError.revenuePeriodNotFound
        }
        rows[idx] = try transform(rows[idx], inv, rows)

        let paid = Self.sumConfirmedRevenueSharePaid(rows: rows)
        let cap = Self.revenueShareCapAmount(for: inv)
        var updates: [String: Any] = [
            "revenueSharePeriods": rows.map { $0.firestoreMap() },
            "receivedAmount": paid,
            "updatedAt": Timestamp(date: Date())
        ]
        let fullyClosedByRows = rows.allSatisfy { $0.status == .confirmed_paid }
        if fullyClosedByRows || paid >= cap {
            updates["status"] = "completed"
            updates["fundingStatus"] = FundingStatus.closed.rawValue
        }
        try await invRef.updateData(updates)
    }

    private static func revenueShareCapAmount(for inv: InvestmentListing) -> Double {
        if let t = inv.agreement?.termsSnapshot.targetReturnAmount, t > 0 {
            return t
        }
        return round2(inv.investmentAmount * 1.25)
    }

    private static func sumConfirmedRevenueSharePaid(rows: [RevenueSharePeriod]) -> Double {
        rows
            .filter { $0.status == .confirmed_paid }
            .reduce(0) { $0 + max(0, $1.actualPaidAmount ?? $1.expectedShareAmount ?? 0) }
    }

    private static func round2(_ x: Double) -> Double {
        (x * 100).rounded() / 100
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
        let representativeRow = activeRows.sorted { $0.recencyDate > $1.recencyDate }.first
        var termsSnapshot = opportunity.terms
        if let representativeRow {
            let canonicalOffer = try? await fetchLatestOfferRecord(
                investmentId: representativeRow.id,
                opportunityId: opportunity.id,
                seekerUid: seekerId
            )
            switch opportunity.investmentType {
            case .loan:
                if let acceptedRate = canonicalOffer?.interestRate ?? representativeRow.offeredInterestRate ?? representativeRow.finalInterestRate {
                    termsSnapshot.interestRate = acceptedRate
                }
                if let acceptedMonths = canonicalOffer?.timelineMonths ?? representativeRow.offeredTimelineMonths ?? representativeRow.finalTimelineMonths {
                    termsSnapshot.repaymentTimelineMonths = acceptedMonths
                }
            case .equity:
                if let acceptedEquity = canonicalOffer?.interestRate ?? representativeRow.offeredInterestRate ?? representativeRow.finalInterestRate {
                    termsSnapshot.equityPercentage = acceptedEquity
                }
                if let acceptedMonths = canonicalOffer?.timelineMonths ?? representativeRow.offeredTimelineMonths ?? representativeRow.finalTimelineMonths {
                    termsSnapshot.equityTimelineMonths = acceptedMonths
                }
            }
        }
        let agreementPayload = Self.makeAgreementPayload(
            opportunity: opportunity,
            termsSnapshot: termsSnapshot,
            agreementId: opportunity.id,
            requiredSignerIds: requiredSignerIds,
            linkedInvestmentIds: activeRows.map(\.id),
            participants: participants,
            investorName: representativeInvestor,
            seekerName: seekerDisplay,
            investmentAmount: maxAmount,
            at: now
        )

        let moaBatch = db.batch()
        let pendingPayload: [String: Any] = [
            "agreementStatus": AgreementStatus.pending_signatures.rawValue,
            "agreementGeneratedAt": Timestamp(date: now),
            "agreement": agreementPayload,
            "updatedAt": Timestamp(date: now)
        ]
        for row in activeRows {
            moaBatch.updateData(pendingPayload, forDocument: db.collection("investments").document(row.id))
        }
        try await moaBatch.commit()
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
        termsSnapshot: OpportunityTerms,
        agreementId: String,
        requiredSignerIds: [String],
        linkedInvestmentIds: [String],
        participants: [AgreementSignerSnapshot],
        investorName: String,
        seekerName: String,
        investmentAmount: Double,
        at: Date
    ) -> [String: Any] {
        let termsPayload = OpportunityFirestoreCoding.termsDictionary(from: termsSnapshot, type: opportunity.investmentType)
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
            "linkedInvestmentIds": linkedInvestmentIds,
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

    /// Amount for this investor’s ticket: listing split for multi-investor listings unless the caller passes an explicit offer amount.
    private static func resolveRequestedTicketAmount(
        opp: OpportunityListing,
        proposedAmount: Double?
    ) -> Double {
        let cap = max(1, opp.maximumInvestors ?? 1)
        if cap <= 1 {
            return proposedAmount ?? opp.amountRequested
        }
        if let proposedAmount, proposedAmount > 0 {
            return proposedAmount
        }
        return fixedEqualSplitAmount(total: opp.amountRequested, investors: cap)
    }

    static func fixedEqualSplitAmount(total: Double, investors: Int) -> Double {
        guard total > 0, investors > 0 else { return 0 }
        let raw = total / Double(investors)
        return (raw * 100).rounded() / 100
    }

    private static func lkrAmountText(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
    }

    private func fetchLatestOfferRecord(investmentId: String, opportunityId: String, seekerUid: String) async throws -> OfferRecord? {
        let byInvestment = try await db.collection("offers")
            .whereField("investmentId", isEqualTo: investmentId)
            .whereField("seekerId", isEqualTo: seekerUid)
            .limit(to: 20)
            .getDocuments(source: .server)
        let docs = byInvestment.documents.sorted {
            let l = ($0.data()["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            let r = ($1.data()["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            return l > r
        }
        if let first = docs.first, let parsed = Self.offerRecord(from: first.data()) {
            return parsed
        }
        let byOpportunity = try await db.collection("offers")
            .whereField("opportunityId", isEqualTo: opportunityId)
            .whereField("seekerId", isEqualTo: seekerUid)
            .limit(to: 50)
            .getDocuments(source: .server)
        let fallback = byOpportunity.documents
            .filter { (($0.data()["investmentId"] as? String) ?? "") == investmentId }
            .sorted {
                let l = ($0.data()["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                let r = ($1.data()["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                return l > r
            }
            .first
        guard let fallback else { return nil }
        return Self.offerRecord(from: fallback.data())
    }

    private func markOfferAccepted(investmentId: String, opportunityId: String, seekerId: String, at now: Date) async throws {
        let byInvestment = try await db.collection("offers")
            .whereField("investmentId", isEqualTo: investmentId)
            .whereField("seekerId", isEqualTo: seekerId)
            .limit(to: 20)
            .getDocuments(source: .server)
        let offerDocs = byInvestment.documents.isEmpty
            ? try await db.collection("offers")
                .whereField("opportunityId", isEqualTo: opportunityId)
                .whereField("seekerId", isEqualTo: seekerId)
                .limit(to: 50)
                .getDocuments(source: .server)
            : byInvestment
        let matches = offerDocs.documents.filter {
            (($0.data()["investmentId"] as? String) ?? "") == investmentId
        }
        guard !matches.isEmpty else { return }
        let batch = db.batch()
        for doc in matches {
            batch.updateData([
                "status": InvestmentOfferStatus.accepted.rawValue,
                "acceptedAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now)
            ], forDocument: doc.reference)
        }
        try await batch.commit()
    }

    private static func offerRecord(from data: [String: Any]) -> OfferRecord? {
        guard let amount = parseDoubleValue(data["amount"]),
              amount > 0,
              let rate = parseDoubleValue(data["interestRate"]),
              rate > 0,
              let months = parseIntValue(data["timelineMonths"]),
              months > 0 else {
            return nil
        }
        return OfferRecord(amount: amount, interestRate: rate, timelineMonths: months)
    }

    private static func parseDoubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String {
            let cleaned = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }
        return nil
    }

    private static func parseIntValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let direct = Int(cleaned) { return direct }
            let digits = cleaned.filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }
}
