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

        let investmentType = InvestmentType.parse(data["investmentType"] as? String)

        let amountRequested = Self.parseAmount(from: data)
        let minimumInvestment = Self.parseMinimumInvestment(from: data, fallbackTotal: amountRequested)

        let maximumInvestors: Int? = {
            if let v = data["maximumInvestors"] as? Int { return v > 0 ? v : nil }
            if let n = data["maximumInvestors"] as? NSNumber {
                let i = n.intValue
                return i > 0 ? i : nil
            }
            if let v = data["maximumInvestors"] as? Int64 {
                let i = Int(v)
                return i > 0 ? i : nil
            }
            return nil
        }()

        var terms = OpportunityFirestoreCoding.parseTerms(from: data, type: investmentType)

        // Legacy listings: only top-level loan fields.
        if investmentType == .loan {
            if terms.interestRate == nil {
                terms.interestRate = Self.parseInterest(from: data)
            }
            if terms.repaymentTimelineMonths == nil {
                terms.repaymentTimelineMonths = Self.parseTimelineMonths(from: data)
            }
            if terms.repaymentFrequency == nil, let raw = data["repaymentFrequency"] as? String {
                terms.repaymentFrequency = RepaymentFrequency(rawValue: raw.lowercased())
            }
        }

        let useOfFunds = (data["useOfFunds"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let incomeGenerationMethod = (data["incomeGenerationMethod"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let milestones = OpportunityFirestoreCoding.milestones(from: data)

        let location = (data["location"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let riskLevel = RiskLevel.parse(data["riskLevel"] as? String)
        let verificationStatus = VerificationStatus.parse(data["verificationStatus"] as? String)
        let isNegotiable: Bool = {
            if let v = data["isNegotiable"] as? Bool { return v }
            if let n = data["isNegotiable"] as? NSNumber { return n.boolValue }
            return true
        }()

        let documentURLs = Self.parseStringArray(data["documentURLs"])

        let rawStatus = (data["status"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let status = rawStatus.isEmpty ? "open" : rawStatus
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
            investmentType: investmentType,
            amountRequested: amountRequested,
            minimumInvestment: minimumInvestment,
            maximumInvestors: maximumInvestors,
            terms: terms,
            useOfFunds: useOfFunds,
            incomeGenerationMethod: incomeGenerationMethod,
            milestones: milestones,
            location: location,
            riskLevel: riskLevel,
            verificationStatus: verificationStatus,
            isNegotiable: isNegotiable,
            documentURLs: documentURLs,
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

    private static func parseMinimumInvestment(from data: [String: Any], fallbackTotal: Double) -> Double {
        if let d = numberToDouble(data["minimumInvestment"]), d > 0 { return d }
        return min(fallbackTotal, max(1, fallbackTotal * 0.01))
    }

    private static func parseAmount(from data: [String: Any]) -> Double {
        numberToDouble(data["amountRequested"])
            ?? numberToDouble(data["amount"])
            ?? 0
    }

    /// Firestore may store numbers as `Double`, `Int`, `Int64`, or `NSNumber`.
    private static func numberToDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let i = value as? Int { return Double(i) }
        if let i = value as? Int64 { return Double(i) }
        if let s = value as? String {
            return Double(s.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    private static func parseInterest(from data: [String: Any]) -> Double {
        numberToDouble(data["interestRate"]) ?? 0
    }

    private static func collectImageReferences(from data: [String: Any]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func appendParsedArray(_ key: String) {
            for s in parseStringArray(data[key]) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !seen.contains(t) {
                    seen.insert(t)
                    out.append(t)
                }
            }
        }
        appendParsedArray("imageURLs")
        appendParsedArray("imageStoragePaths")
        if out.isEmpty { appendParsedArray("images") }
        if out.isEmpty, let s = data["imageStoragePath"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !seen.contains(t) { seen.insert(t); out.append(t) }
        }
        if out.isEmpty, let s = data["imageURL"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !seen.contains(t) { seen.insert(t); out.append(t) }
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
        if let v = data["repaymentTimelineMonths"] as? Int64 { return max(1, Int(v)) }
        if let s = data["repaymentTimeline"] as? String {
            let digits = s.filter(\.isNumber)
            if let m = Int(digits), m > 0 { return m }
        }
        return 1
    }
}
