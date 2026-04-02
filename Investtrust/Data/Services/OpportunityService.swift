//
//  OpportunityService.swift
//  Investtrust
//

import FirebaseFirestore
import FirebaseStorage
import Foundation

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
    ) async throws -> SeekerOpportunityItem {
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
        var imageStoragePaths: [String] = []
        var videoURL: String?
        var videoStoragePath: String?
        var mediaWarnings: [String] = []

        for (index, imageData) in imageDataList.enumerated() {
            let imagePath = "opportunities/\(userID)/\(opportunityID)/image-\(index + 1).jpg"
            let imageRef = storage.reference(withPath: imagePath)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            do {
                _ = try await withTimeout(seconds: 25) {
                    try await imageRef.putDataAsync(imageData, metadata: metadata)
                }
                imageStoragePaths.append(imagePath)
            } catch {
                mediaWarnings.append("Image \(index + 1) failed to upload.")
            }
        }
        imageURLs = imageStoragePaths

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
                videoURL = videoPath
            } catch {
                mediaWarnings.append("Video failed to upload.")
            }
        }

        let payload: [String: Any] = [
            "ownerId": userID,
            "title": normalizedTitle,
            "category": normalizedCategory,
            "description": normalizedDescription,
            "amountRequested": amountRequested,
            "interestRate": interestRate,
            "repaymentTimelineMonths": repaymentTimelineMonths,
            // Legacy fields kept for existing UI compatibility.
            "amount": String(amountRequested),
            "repaymentTimeline": "\(repaymentTimelineMonths) months",
            "imageURLs": imageURLs,
            "imageStoragePaths": imageStoragePaths,
            "videoURL": videoURL as Any,
            "videoStoragePath": videoStoragePath as Any,
            "mediaCount": [
                "images": imageStoragePaths.count,
                "hasVideo": videoStoragePath != nil
            ],
            "status": "open",
            "mediaWarnings": mediaWarnings,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]

        try await withTimeout(seconds: 12) {
            try await doc.setData(payload)
        }

        return SeekerOpportunityItem(
            id: opportunityID,
            title: normalizedTitle,
            category: normalizedCategory,
            amount: String(amountRequested),
            interestRate: String(interestRate),
            repaymentTimeline: "\(repaymentTimelineMonths) months",
            imageURLs: imageURLs,
            videoURL: videoURL
        )
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

