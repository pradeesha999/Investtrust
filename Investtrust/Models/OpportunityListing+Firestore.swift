import FirebaseFirestore
import Foundation

extension OpportunityListing {
    init(document: QueryDocumentSnapshot) {
        self.init(documentID: document.documentID, data: document.data())
    }

    init(documentID: String, data: [String: Any]) {
        let ownerId = data["ownerId"] as? String ?? ""

        let title = (data["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTitle = (title?.isEmpty == false) ? title! : "Untitled"

        let category = (data["category"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let description = (data["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let amountRequested = Self.parseAmount(from: data)
        let interestRate = Self.parseInterest(from: data)
        let repaymentTimelineMonths = Self.parseTimelineMonths(from: data)

        let status = (data["status"] as? String)?.lowercased() ?? "open"

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

        let imageStoragePaths = Self.collectImageReferences(from: data)

        var videoURL = Self.firstNonEmptyString(
            from: data,
            keys: ["videoURL", "videoDownloadURL", "video_download_url"]
        )
        var videoStoragePath = Self.firstNonEmptyString(
            from: data,
            keys: ["videoStoragePath", "videoPath", "video_storage_path"]
        )
        if let media = data["media"] as? [String: Any] {
            if videoURL == nil {
                videoURL = Self.firstNonEmptyString(
                    from: media,
                    keys: ["videoURL", "videoDownloadURL", "url"]
                )
            }
            if videoStoragePath == nil {
                videoStoragePath = Self.firstNonEmptyString(
                    from: media,
                    keys: ["videoStoragePath", "storagePath", "path"]
                )
            }
        }
        if videoURL == nil, let v = data["video"] as? String {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { videoURL = t }
        }
        if let videoMap = data["video"] as? [String: Any] {
            if videoURL == nil {
                videoURL = Self.firstNonEmptyString(
                    from: videoMap,
                    keys: ["videoURL", "url", "downloadURL", "httpsURL", "link"]
                )
            }
            if videoStoragePath == nil {
                videoStoragePath = Self.firstNonEmptyString(
                    from: videoMap,
                    keys: ["videoStoragePath", "storagePath", "path", "gsPath"]
                )
            }
        }

        let mediaWarnings = Self.parseStringArray(data["mediaWarnings"])
        let imagePublicIds = Self.parseStringArray(data["imagePublicIds"])
        let videoPublicId = Self.firstNonEmptyString(from: data, keys: ["videoPublicId", "video_public_id"])

        self.init(
            id: documentID,
            ownerId: ownerId,
            title: rawTitle,
            category: category,
            description: description,
            amountRequested: amountRequested,
            interestRate: interestRate,
            repaymentTimelineMonths: repaymentTimelineMonths,
            status: status,
            createdAt: createdAt,
            imageStoragePaths: imageStoragePaths,
            videoStoragePath: videoStoragePath,
            videoURL: videoURL,
            mediaWarnings: mediaWarnings,
            imagePublicIds: imagePublicIds,
            videoPublicId: videoPublicId
        )
    }

    private static func parseAmount(from data: [String: Any]) -> Double {
        if let v = data["amountRequested"] as? Double { return v }
        if let n = data["amountRequested"] as? NSNumber { return n.doubleValue }
        if let v = data["amount"] as? Double { return v }
        if let n = data["amount"] as? NSNumber { return n.doubleValue }
        if let s = data["amount"] as? String {
            let cleaned = s.replacingOccurrences(of: ",", with: "")
            return Double(cleaned) ?? 0
        }
        return 0
    }

    private static func parseInterest(from data: [String: Any]) -> Double {
        if let v = data["interestRate"] as? Double { return v }
        if let n = data["interestRate"] as? NSNumber { return n.doubleValue }
        if let s = data["interestRate"] as? String {
            return Double(s.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        return 0
    }

    /// Firestore may store paths under several keys depending on app version or manual edits.
    private static func collectImageReferences(from data: [String: Any]) -> [String] {
        var out: [String] = []
        func appendStrings(_ arr: [String]?) {
            guard let arr else { return }
            for s in arr {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append(t) }
            }
        }
        appendStrings(data["imageStoragePaths"] as? [String])
        if out.isEmpty { appendStrings(data["imageURLs"] as? [String]) }
        if out.isEmpty { appendStrings(data["images"] as? [String]) }
        if out.isEmpty, let s = data["imageStoragePath"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(t) }
        }
        if out.isEmpty, let s = data["imageURL"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(t) }
        }
        return out
    }

    private static func parseStringArray(_ value: Any?) -> [String] {
        if let arr = value as? [String] {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let arr = value as? [Any] {
            return arr.compactMap { $0 as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    private static func firstNonEmptyString(from data: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let s = data[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    private static func parseTimelineMonths(from data: [String: Any]) -> Int {
        if let v = data["repaymentTimelineMonths"] as? Int { return max(1, v) }
        if let n = data["repaymentTimelineMonths"] as? NSNumber { return max(1, n.intValue) }
        if let s = data["repaymentTimeline"] as? String {
            let digits = s.filter(\.isNumber)
            if let m = Int(digits), m > 0 { return m }
        }
        return 1
    }
}
