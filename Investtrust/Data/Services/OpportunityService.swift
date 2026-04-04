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

        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "Enter a valid amount (numbers only)."
            case .invalidInterestRate:
                return "Enter a valid interest rate (for example 12.5)."
            case .invalidTimeline:
                return "Enter a valid repayment timeline in months."
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

        var imageStoragePaths: [String] = []
        var videoStoragePath: String?
        var mediaWarnings: [String] = []

        for (index, imageData) in imageDataList.enumerated() {
            let imagePath = "opportunities/\(userID)/\(opportunityID)/image-\(index + 1).jpg"
            let imageRef = storage.reference(withPath: imagePath)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            let payload = Self.jpegPayloadForUpload(from: imageData)
            do {
                _ = try await withTimeout(seconds: 25) {
                    try await imageRef.putDataAsync(payload, metadata: metadata)
                }
                imageStoragePaths.append(imagePath)
            } catch {
                mediaWarnings.append("Image \(index + 1) failed to upload.")
            }
        }

        if let videoData {
            let videoPath = "opportunities/\(userID)/\(opportunityID)/video.mov"
            let videoRef = storage.reference(withPath: videoPath)
            let metadata = StorageMetadata()
            metadata.contentType = "video/quicktime"
            do {
                _ = try await withTimeout(seconds: 30) {
                    try await videoRef.putDataAsync(videoData, metadata: metadata)
                }
                videoStoragePath = videoPath
            } catch {
                mediaWarnings.append("Video failed to upload.")
            }
        }

        let now = Date()
        let payload: [String: Any] = [
            "ownerId": userID,
            "title": normalizedTitle,
            "category": normalizedCategory,
            "description": normalizedDescription,
            "amountRequested": amountRequested,
            "interestRate": interestRate,
            "repaymentTimelineMonths": repaymentTimelineMonths,
            "imageStoragePaths": imageStoragePaths,
            "videoStoragePath": videoStoragePath as Any,
            "mediaCount": [
                "images": imageStoragePaths.count,
                "hasVideo": videoStoragePath != nil
            ],
            "status": "open",
            "mediaWarnings": mediaWarnings,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]

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
            imageStoragePaths: imageStoragePaths,
            videoStoragePath: videoStoragePath
        )
    }

    func fetchMarketListings(limit: Int = 50) async throws -> [OpportunityListing] {
        let base = db.collection("opportunities")

        do {
            let snapshot = try await base
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents
                .map { OpportunityListing(document: $0) }
                .filter { $0.status == "open" }
        } catch {
            let snapshot = try await base.limit(to: limit).getDocuments()
            return snapshot.documents
                .map { OpportunityListing(document: $0) }
                .filter { $0.status == "open" }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    func fetchSeekerListings(ownerId: String, limit: Int = 50) async throws -> [OpportunityListing] {
        let base = db.collection("opportunities")

        do {
            let snapshot = try await base
                .whereField("ownerId", isEqualTo: ownerId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.map { OpportunityListing(document: $0) }
        } catch {
            let snapshot = try await base.limit(to: 100).getDocuments()
            let rows = snapshot.documents
                .map { OpportunityListing(document: $0) }
                .filter { $0.ownerId == ownerId }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return Array(rows.prefix(limit))
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
