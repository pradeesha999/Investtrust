import FirebaseFirestore
import FirebaseStorage
import Foundation
import UIKit

/// Writes and reads `opportunities` documents (see `OpportunityListing` + `OpportunityListing+Firestore`).
final class OpportunityService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    enum OpportunityServiceError: LocalizedError {
        case invalidAmount
        case invalidInterestRate
        case invalidTimeline
        case invalidTerms
        case invalidMinimum
        case notOwner
        case blockedByActiveInvestmentRequests

        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "Enter a valid funding goal (numbers only)."
            case .invalidInterestRate:
                return "Enter a valid interest rate (for example 12.5)."
            case .invalidTimeline:
                return "Enter a valid repayment timeline in months."
            case .invalidTerms:
                return "Fill in all required fields for the selected investment type."
            case .invalidMinimum:
                return "Minimum investment must be greater than zero and not more than the funding goal."
            case .notOwner:
                return "You don’t have permission to change this listing."
            case .blockedByActiveInvestmentRequests:
                return "You have pending investment requests. Decline them before editing or deleting this listing."
            }
        }
    }

    func createOpportunity(
        userID: String,
        draft: OpportunityDraft,
        imageDataList: [Data],
        videoData: Data?
    ) async throws -> OpportunityListing {
        let normalizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUseOfFunds = draft.useOfFunds.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amountRequested = Self.parseDouble(from: draft.amount), amountRequested > 0 else {
            throw OpportunityServiceError.invalidAmount
        }

        let terms = try Self.validatedTerms(from: draft)

        let minRaw = draft.minimumInvestment.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimumInvestment: Double
        if minRaw.isEmpty {
            minimumInvestment = min(amountRequested, max(1, amountRequested * 0.01))
        } else {
            guard let m = Self.parseDouble(from: minRaw), m > 0, m <= amountRequested else {
                throw OpportunityServiceError.invalidMinimum
            }
            minimumInvestment = m
        }

        let maxInvestors: Int? = {
            let t = draft.maximumInvestors.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let n = Int(t.filter(\.isNumber)), n > 0 else { return nil }
            return n
        }()

        let doc = db.collection("opportunities").document()
        let opportunityID = doc.documentID

        var imageURLs: [String] = []
        var imagePublicIds: [String] = []
        var videoStoragePath: String?
        var videoHTTPSURL: String?
        var videoPublicId: String?
        var mediaWarnings: [String] = []

        for (index, imageData) in imageDataList.enumerated() {
            let payload = Self.jpegPayloadForUpload(from: imageData)
            let filename = "opportunity-\(opportunityID)-\(index + 1).jpg"
            do {
                let asset = try await withTimeout(seconds: 60) {
                    try await CloudinaryImageUploadClient.uploadImageData(payload, filename: filename)
                }
                imageURLs.append(asset.secureURL)
                if let pid = asset.publicId {
                    imagePublicIds.append(pid)
                }
            } catch {
                mediaWarnings.append("Image \(index + 1) failed to upload.")
            }
        }

        if let videoData {
            if videoData.isEmpty {
                mediaWarnings.append("Video was empty — try choosing the clip again.")
            } else {
                let filename = "opportunity-\(opportunityID)-video.mp4"
                do {
                    let asset = try await withTimeout(seconds: 600) {
                        try await CloudinaryVideoUploadClient.uploadVideoData(videoData, filename: filename)
                    }
                    videoHTTPSURL = asset.secureURL
                    videoPublicId = asset.publicId
                    videoStoragePath = nil
                } catch {
                    mediaWarnings.append("Video failed: \(error.localizedDescription)")
                }
            }
        }

        let milestonesPayload = Self.milestonesPayload(from: draft.milestones)
        let termsMap = OpportunityFirestoreCoding.termsDictionary(from: terms, type: draft.investmentType)

        let now = Date()
        var payload: [String: Any] = [
            "ownerId": userID,
            "title": normalizedTitle,
            "category": normalizedCategory,
            "description": normalizedDescription,
            "location": normalizedLocation,
            "investmentType": draft.investmentType.rawValue,
            "amountRequested": amountRequested,
            "minimumInvestment": minimumInvestment,
            "useOfFunds": normalizedUseOfFunds,
            "milestones": milestonesPayload,
            "riskLevel": draft.riskLevel.rawValue,
            "verificationStatus": draft.verificationStatus.rawValue,
            "documentURLs": [String](),
            "terms": termsMap,
            "imageURLs": imageURLs,
            "imagePublicIds": imagePublicIds,
            "videoStoragePath": videoStoragePath as Any,
            "videoPublicId": videoPublicId as Any,
            "status": "open",
            "mediaWarnings": mediaWarnings,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]
        if let maxInvestors {
            payload["maximumInvestors"] = maxInvestors
        }
        if draft.investmentType == .loan {
            if let r = terms.interestRate { payload["interestRate"] = r }
            if let m = terms.repaymentTimelineMonths { payload["repaymentTimelineMonths"] = m }
        }
        if let videoHTTPSURL {
            payload["videoURL"] = videoHTTPSURL
        }

        try await withTimeout(seconds: 12) {
            try await doc.setData(payload)
        }

        let snap = try await doc.getDocument()
        guard let merged = snap.data() else {
            throw NSError(domain: "Investtrust", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not read listing after save."])
        }
        return OpportunityListing(documentID: opportunityID, data: merged)
    }

    /// If the listing has a Storage path but no `videoURL`, fetch the download URL and save it (owner only). Lets investors play video for listings created before `videoURL` was written.
    func syncVideoDownloadURLIfNeeded(opportunityId: String, ownerId: String) async throws -> OpportunityListing? {
        let ref = db.collection("opportunities").document(opportunityId)
        let snapshot = try await ref.getDocument()
        guard let data = snapshot.data(), (data["ownerId"] as? String) == ownerId else {
            throw OpportunityServiceError.notOwner
        }
        let existingURL = (data["videoURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !existingURL.isEmpty { return nil }
        let rawPath = (data["videoStoragePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawPath.isEmpty else { return nil }
        let path = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
        let storageRef = storage.reference(withPath: path)
        let url = try await storageRef.downloadURL()
        let now = Date()
        try await ref.updateData([
            "videoURL": url.absoluteString,
            "updatedAt": Timestamp(date: now)
        ])
        var merged = data
        merged["videoURL"] = url.absoluteString
        merged["updatedAt"] = Timestamp(date: now)
        return OpportunityListing(documentID: opportunityId, data: merged)
    }

    /// Latest opportunity document (e.g. refresh `videoURL` after seeker sync).
    func fetchOpportunity(opportunityId: String) async throws -> OpportunityListing? {
        let snapshot = try await db.collection("opportunities").document(opportunityId).getDocument()
        guard let data = snapshot.data() else { return nil }
        return OpportunityListing(documentID: opportunityId, data: data)
    }

    func fetchMarketListings(limit: Int = 50) async throws -> [OpportunityListing] {
        let base = db.collection("opportunities")
        // Prefer ordered query when index exists; otherwise fetch and sort in memory (no composite index required).
        do {
            let snapshot = try await base
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents
                .map { OpportunityListing(document: $0) }
                .filter { $0.status == "open" }
        } catch {
            let snapshot = try await base.limit(to: max(limit * 3, 100)).getDocuments()
            let rows = snapshot.documents
                .map { OpportunityListing(document: $0) }
                .filter { $0.status == "open" }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return Array(rows.prefix(limit))
        }
    }

    /// Updates listing fields (media unchanged). Blocked while any non-declined investment request exists for this opportunity.
    func updateOpportunity(
        opportunityId: String,
        ownerId: String,
        draft: OpportunityDraft
    ) async throws -> OpportunityListing {
        let normalizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUseOfFunds = draft.useOfFunds.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amountRequested = Self.parseDouble(from: draft.amount), amountRequested > 0 else {
            throw OpportunityServiceError.invalidAmount
        }

        let terms = try Self.validatedTerms(from: draft)

        let minRaw = draft.minimumInvestment.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimumInvestment: Double
        if minRaw.isEmpty {
            minimumInvestment = min(amountRequested, max(1, amountRequested * 0.01))
        } else {
            guard let m = Self.parseDouble(from: minRaw), m > 0, m <= amountRequested else {
                throw OpportunityServiceError.invalidMinimum
            }
            minimumInvestment = m
        }

        let maxInvestors: Int? = {
            let t = draft.maximumInvestors.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let n = Int(t.filter(\.isNumber)), n > 0 else { return nil }
            return n
        }()

        let ref = db.collection("opportunities").document(opportunityId)
        let snapshot = try await ref.getDocument()
        guard let existing = snapshot.data(), (existing["ownerId"] as? String) == ownerId else {
            throw OpportunityServiceError.notOwner
        }
        if try await hasBlockingInvestmentRequests(opportunityId: opportunityId) {
            throw OpportunityServiceError.blockedByActiveInvestmentRequests
        }

        let milestonesPayload = Self.milestonesPayload(from: draft.milestones)
        let termsMap = OpportunityFirestoreCoding.termsDictionary(from: terms, type: draft.investmentType)

        let now = Date()
        var fields: [String: Any] = [
            "title": normalizedTitle,
            "category": normalizedCategory,
            "description": normalizedDescription,
            "location": normalizedLocation,
            "investmentType": draft.investmentType.rawValue,
            "amountRequested": amountRequested,
            "minimumInvestment": minimumInvestment,
            "useOfFunds": normalizedUseOfFunds,
            "milestones": milestonesPayload,
            "riskLevel": draft.riskLevel.rawValue,
            "verificationStatus": draft.verificationStatus.rawValue,
            "terms": termsMap,
            "updatedAt": Timestamp(date: now)
        ]
        if let maxInvestors {
            fields["maximumInvestors"] = maxInvestors
        } else {
            fields["maximumInvestors"] = FieldValue.delete()
        }

        if draft.investmentType == .loan {
            if let r = terms.interestRate { fields["interestRate"] = r }
            if let m = terms.repaymentTimelineMonths { fields["repaymentTimelineMonths"] = m }
        } else {
            fields["interestRate"] = FieldValue.delete()
            fields["repaymentTimelineMonths"] = FieldValue.delete()
        }

        try await withTimeout(seconds: 12) {
            try await ref.updateData(fields)
        }

        let mergedSnap = try await ref.getDocument()
        guard let merged = mergedSnap.data() else {
            throw NSError(domain: "Investtrust", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not read listing after update."])
        }
        return OpportunityListing(documentID: opportunityId, data: merged)
    }

    /// Deletes the opportunity and related `investments` rows for this listing. Blocked while any active (non-declined) request exists.
    func deleteOpportunity(opportunityId: String, ownerId: String) async throws {
        let ref = db.collection("opportunities").document(opportunityId)
        let snapshot = try await ref.getDocument()
        guard let existing = snapshot.data(), (existing["ownerId"] as? String) == ownerId else {
            throw OpportunityServiceError.notOwner
        }
        if try await hasBlockingInvestmentRequests(opportunityId: opportunityId) {
            throw OpportunityServiceError.blockedByActiveInvestmentRequests
        }

        let listing = OpportunityListing(documentID: opportunityId, data: existing)
        await CloudinaryDestroyClient.deleteAssetsForOpportunity(
            imagePublicIds: listing.imagePublicIds,
            videoPublicId: listing.videoPublicId,
            imageDeliveryURLs: listing.imageStoragePaths,
            videoDeliveryURL: listing.videoURL
        )

        if let rawPath = (existing["videoStoragePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty {
            let path = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
            try? await storage.reference(withPath: path).delete()
        }

        let related = try await db.collection("investments")
            .whereField("opportunityId", isEqualTo: opportunityId)
            .getDocuments()

        let batch = db.batch()
        for doc in related.documents {
            batch.deleteDocument(doc.reference)
        }
        batch.deleteDocument(ref)
        try await withTimeout(seconds: 20) {
            try await batch.commit()
        }
    }

    private func hasBlockingInvestmentRequests(opportunityId: String) async throws -> Bool {
        let snap = try await db.collection("investments")
            .whereField("opportunityId", isEqualTo: opportunityId)
            .getDocuments()
        for doc in snap.documents {
            guard let inv = InvestmentListing(id: doc.documentID, data: doc.data()) else { continue }
            if inv.blocksSeekerFromManagingOpportunity {
                return true
            }
        }
        return false
    }

    func fetchSeekerListings(ownerId: String, limit: Int = 50) async throws -> [OpportunityListing] {
        let base = db.collection("opportunities")
        // Avoid composite index (ownerId + createdAt): filter only, then sort in memory.
        let snapshot = try await base
            .whereField("ownerId", isEqualTo: ownerId)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents
            .map { OpportunityListing(document: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Same rules as `createOpportunity` / `updateOpportunity` — use for client-side step validation.
    static func validateDraftTerms(_ draft: OpportunityDraft) throws -> OpportunityTerms {
        try validatedTerms(from: draft)
    }

    private static func validatedTerms(from draft: OpportunityDraft) throws -> OpportunityTerms {
        switch draft.investmentType {
        case .loan:
            guard let r = Self.parseDouble(from: draft.interestRate), r >= 0 else {
                throw OpportunityServiceError.invalidInterestRate
            }
            let tl = draft.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let m = Self.parseInt(from: tl), m > 0 else {
                throw OpportunityServiceError.invalidTimeline
            }
            var t = OpportunityTerms()
            t.interestRate = r
            t.repaymentTimelineMonths = m
            t.repaymentFrequency = draft.repaymentFrequency
            return t
        case .equity:
            guard let p = Self.parseDouble(from: draft.equityPercentage), p > 0, p <= 100 else {
                throw OpportunityServiceError.invalidTerms
            }
            var t = OpportunityTerms()
            t.equityPercentage = p
            let bv = draft.businessValuation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bv.isEmpty, let v = Self.parseDouble(from: bv), v > 0 {
                t.businessValuation = v
            }
            let exit = draft.exitPlan.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !exit.isEmpty else { throw OpportunityServiceError.invalidTerms }
            t.exitPlan = exit
            return t
        case .revenue_share:
            guard let p = Self.parseDouble(from: draft.revenueSharePercent), p > 0 else {
                throw OpportunityServiceError.invalidTerms
            }
            guard let target = Self.parseDouble(from: draft.targetReturnAmount), target > 0 else {
                throw OpportunityServiceError.invalidTerms
            }
            let md = draft.maxDurationMonths.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let maxM = Self.parseInt(from: md), maxM > 0 else {
                throw OpportunityServiceError.invalidTimeline
            }
            var t = OpportunityTerms()
            t.revenueSharePercent = p
            t.targetReturnAmount = target
            t.maxDurationMonths = maxM
            return t
        case .project:
            let val = draft.expectedReturnValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !val.isEmpty else { throw OpportunityServiceError.invalidTerms }
            var t = OpportunityTerms()
            t.expectedReturnType = draft.expectedReturnType
            t.expectedReturnValue = val
            t.completionDate = draft.completionDate
            return t
        case .custom:
            let s = draft.customTermsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { throw OpportunityServiceError.invalidTerms }
            var t = OpportunityTerms()
            t.customTermsSummary = s
            return t
        }
    }

    private static func milestonesPayload(from items: [MilestoneDraft]) -> [[String: Any]] {
        items.compactMap { d -> [String: Any]? in
            let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = d.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty && desc.isEmpty { return nil }
            var o: [String: Any] = [
                "title": title.isEmpty ? "Milestone" : title,
                "description": desc
            ]
            if let date = d.expectedDate {
                o["expectedDate"] = Timestamp(date: date)
            }
            return o
        }
    }

    /// Photos picker / camera may supply HEIC/PNG; we always store JPEG bytes so downloads decode reliably as `image/jpeg`.
    private static func jpegPayloadForUpload(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.88) ?? data
    }

    private static func parseDouble(from text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private static func parseInt(from text: String) -> Int? {
        let digitsOnly = text.filter(\.isNumber)
        return Int(digitsOnly)
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(
                    domain: "Investtrust",
                    code: 408,
                    userInfo: [NSLocalizedDescriptionKey: "Request timed out. Check Firebase setup/rules and network, then try again."]
                )
            }

            guard let first = try await group.next() else {
                throw NSError(
                    domain: "Investtrust",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected empty async result."]
                )
            }
            group.cancelAll()
            return first
        }
    }
}
