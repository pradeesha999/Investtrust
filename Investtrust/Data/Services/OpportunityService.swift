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
        case notOwner
        case blockedByActiveInvestmentRequests

        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "Enter a valid amount (numbers only)."
            case .invalidInterestRate:
                return "Enter a valid interest rate (for example 12.5)."
            case .invalidTimeline:
                return "Enter a valid repayment timeline in months."
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
        let normalizedTimelineText = draft.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amountRequested = Self.parseDouble(from: draft.amount), amountRequested > 0 else {
            throw OpportunityServiceError.invalidAmount
        }
        guard let interestRate = Self.parseDouble(from: draft.interestRate), interestRate >= 0 else {
            throw OpportunityServiceError.invalidInterestRate
        }
        guard let repaymentTimelineMonths = Self.parseInt(from: normalizedTimelineText), repaymentTimelineMonths > 0 else {
            throw OpportunityServiceError.invalidTimeline
        }

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

        let now = Date()
        var payload: [String: Any] = [
            "ownerId": userID,
            "title": normalizedTitle,
            "category": normalizedCategory,
            "description": normalizedDescription,
            "amountRequested": amountRequested,
            "interestRate": interestRate,
            "repaymentTimelineMonths": repaymentTimelineMonths,
            "imageURLs": imageURLs,
            "imageStoragePaths": [],
            "imagePublicIds": imagePublicIds,
            "videoStoragePath": videoStoragePath as Any,
            "videoPublicId": videoPublicId as Any,
            "mediaCount": [
                "images": imageURLs.count,
                "hasVideo": (videoHTTPSURL != nil) || (videoStoragePath != nil)
            ],
            "status": "open",
            "mediaWarnings": mediaWarnings,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]
        if let videoHTTPSURL {
            payload["videoURL"] = videoHTTPSURL
        }

        try await withTimeout(seconds: 12) {
            try await doc.setData(payload)
        }

        return OpportunityListing(
            id: opportunityID,
            ownerId: userID,
            title: normalizedTitle,
            category: normalizedCategory,
            description: normalizedDescription,
            amountRequested: amountRequested,
            interestRate: interestRate,
            repaymentTimelineMonths: repaymentTimelineMonths,
            status: "open",
            createdAt: now,
            imageStoragePaths: imageURLs,
            videoStoragePath: videoStoragePath,
            videoURL: videoHTTPSURL,
            mediaWarnings: mediaWarnings,
            imagePublicIds: imagePublicIds,
            videoPublicId: videoPublicId
        )
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

    /// Updates listing text/terms only (media unchanged). Blocked while any non-declined investment request exists for this opportunity.
    func updateOpportunity(
        opportunityId: String,
        ownerId: String,
        draft: OpportunityDraft
    ) async throws -> OpportunityListing {
        let normalizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTimelineText = draft.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amountRequested = Self.parseDouble(from: draft.amount), amountRequested > 0 else {
            throw OpportunityServiceError.invalidAmount
        }
        guard let interestRate = Self.parseDouble(from: draft.interestRate), interestRate >= 0 else {
            throw OpportunityServiceError.invalidInterestRate
        }
        guard let repaymentTimelineMonths = Self.parseInt(from: normalizedTimelineText), repaymentTimelineMonths > 0 else {
            throw OpportunityServiceError.invalidTimeline
        }

        let ref = db.collection("opportunities").document(opportunityId)
        let snapshot = try await ref.getDocument()
        guard let existing = snapshot.data(), (existing["ownerId"] as? String) == ownerId else {
            throw OpportunityServiceError.notOwner
        }
        if try await hasBlockingInvestmentRequests(opportunityId: opportunityId) {
            throw OpportunityServiceError.blockedByActiveInvestmentRequests
        }

        let now = Date()
        try await withTimeout(seconds: 12) {
            try await ref.updateData([
                "title": normalizedTitle,
                "category": normalizedCategory,
                "description": normalizedDescription,
                "amountRequested": amountRequested,
                "interestRate": interestRate,
                "repaymentTimelineMonths": repaymentTimelineMonths,
                "updatedAt": Timestamp(date: now)
            ])
        }

        var merged = existing
        merged["title"] = normalizedTitle
        merged["category"] = normalizedCategory
        merged["description"] = normalizedDescription
        merged["amountRequested"] = amountRequested
        merged["interestRate"] = interestRate
        merged["repaymentTimelineMonths"] = repaymentTimelineMonths
        merged["updatedAt"] = Timestamp(date: now)
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
