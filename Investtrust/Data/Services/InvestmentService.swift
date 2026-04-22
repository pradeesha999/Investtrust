import FirebaseFirestore
import FirebaseStorage
import Foundation
import UIKit

final class InvestmentService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let chatService = ChatService()
    private let userService = UserService()

    private static let maxSignatureBytes: Int = 4 * 1024 * 1024
    private static let maxProofBytes: Int = 8 * 1024 * 1024

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
            "investmentAmount": proposedAmount,
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
        let investorDisplay = await Self.investorLegalOrDisplayName(userService: userService, userId: investorId, fallback: "Investor")
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
        guard let investorId = inv.investorId, let seekerUid = inv.seekerId else {
            throw InvestmentServiceError.missingInvestor
        }

        let roleKey: String
        let signerAlreadySigned: Bool
        if userId == investorId {
            roleKey = "investor"
            signerAlreadySigned = (inv.signedByInvestorAt != nil)
        } else if userId == seekerUid {
            roleKey = "seeker"
            signerAlreadySigned = (inv.signedBySeekerAt != nil)
        } else {
            throw InvestmentServiceError.wrongSigner
        }

        // Idempotent retry path: if this signer already signed and both signatures exist,
        // try finalization again instead of failing with "already signed".
        if signerAlreadySigned {
            guard let agreement = inv.agreement else { return }
            guard inv.signedByInvestorAt != nil, inv.signedBySeekerAt != nil else {
                throw InvestmentServiceError.alreadySigned
            }
            try await finalizeMOAAndLoanSchedule(
                invRef: invRef,
                inv: inv,
                agreement: agreement
            )
            return
        }

        let uploaded = try await CloudinaryImageUploadClient.uploadImageData(
            signaturePNG,
            filename: "signature-\(investmentId)-\(roleKey).png",
            mimeType: "image/png"
        )

        let now = Date()
        var updates: [String: Any] = [
            "updatedAt": Timestamp(date: now)
        ]
        if userId == investorId {
            updates["signedByInvestorAt"] = Timestamp(date: now)
            updates["investorSignatureImageURL"] = uploaded.secureURL
            updates["signedByInvestorUserId"] = userId
        } else {
            updates["signedBySeekerAt"] = Timestamp(date: now)
            updates["seekerSignatureImageURL"] = uploaded.secureURL
            updates["signedBySeekerUserId"] = userId
        }
        try await invRef.updateData(updates)

        let mergedSnap = try await invRef.getDocument()
        guard let mergedData = mergedSnap.data(),
              let inv2 = InvestmentListing(id: investmentId, data: mergedData),
              let agreement = inv2.agreement else { return }

        guard inv2.signedByInvestorAt != nil, inv2.signedBySeekerAt != nil else { return }

        try await finalizeMOAAndLoanSchedule(
            invRef: invRef,
            inv: inv2,
            agreement: agreement
        )
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
        agreement: InvestmentAgreementSnapshot
    ) async throws {
        let investmentId = inv.id
        let invSigData: Data
        let seekSigData: Data
        if let invURL = inv.investorSignatureImageURL,
           let seekURL = inv.seekerSignatureImageURL,
           !invURL.isEmpty, !seekURL.isEmpty {
            invSigData = try await Self.downloadSignaturePNGData(from: invURL)
            seekSigData = try await Self.downloadSignaturePNGData(from: seekURL)
        } else {
            let invSigRef = storage.reference().child("investments/\(investmentId)/signatures/investor.png")
            let seekSigRef = storage.reference().child("investments/\(investmentId)/signatures/seeker.png")
            invSigData = try await invSigRef.getDataAsync(maxSize: Int64(Self.maxSignatureBytes))
            seekSigData = try await seekSigRef.getDataAsync(maxSize: Int64(Self.maxSignatureBytes))
        }
        let invImg = UIImage(data: invSigData)
        let seekImg = UIImage(data: seekSigData)
        guard invImg != nil, seekImg != nil else {
            throw InvestmentServiceError.missingSignatureImages
        }

        let pdfData = MOAPDFBuilder.buildPDF(
            agreement: agreement,
            investorSignature: invImg,
            seekerSignature: seekImg
        )
        let hash = MOAPDFBuilder.sha256Hex(of: pdfData)
        var uploadedPDFURL: String?
        var moaUploadErrorMessage: String?
        do {
            let uploadedPDF = try await CloudinaryImageUploadClient.uploadFileData(
                pdfData,
                filename: "moa-\(investmentId).pdf",
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

        if inv.investmentType == .loan {
            let months = max(1, inv.finalTimelineMonths ?? agreement.termsSnapshot.repaymentTimelineMonths ?? 1)
            let rate = inv.finalInterestRate ?? agreement.termsSnapshot.interestRate ?? 0
            let plan = agreement.loanRepaymentPlan
            let start = inv.acceptedAt ?? now
            let schedule = LoanScheduleGenerator.generateSchedule(
                principal: inv.investmentAmount,
                annualRatePercent: rate,
                termMonths: months,
                plan: plan,
                startDate: start
            )
            updates["loanInstallments"] = schedule.map { $0.firestoreMap() }
        }

        try await invRef.updateData(updates)

        if let opId = inv.opportunityId,
           let investorId = inv.investorId,
           let seekerUid = inv.seekerId {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opId,
                seekerId: seekerUid,
                investorId: investorId,
                opportunityTitle: inv.opportunityTitle
            )
            try await chatService.sendMessage(
                chatId: chatId,
                senderId: seekerUid,
                text: "Agreement fully signed. MOA PDF is available on the investment record. Proceed with funding."
            )
        }
    }

    // MARK: - Loan installments

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
        }
        try await invRef.updateData(updates)
    }

    private static func sumConfirmedReceived(rows: [LoanInstallment]) -> Double {
        rows.filter { $0.status == .confirmed_paid }.reduce(0) { $0 + $1.totalDue }
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
