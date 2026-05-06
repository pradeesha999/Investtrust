import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Writes and reads `opportunities` documents (see `OpportunityListing` + `OpportunityListing+Firestore`).
final class OpportunityService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    enum OpportunityServiceError: LocalizedError {
        case invalidAmount
        case invalidInterestRate
        case invalidTimeline
        case invalidTerms
        case incomeGenerationRequired
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
            case .incomeGenerationRequired:
                return "Describe how income will be generated to service this opportunity."
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
        let normalizedIncomeGeneration = draft.incomeGenerationMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIncomeGeneration.isEmpty else {
            throw OpportunityServiceError.incomeGenerationRequired
        }

        guard let amountRequested = Self.parseDouble(from: draft.amount), amountRequested > 0 else {
            throw OpportunityServiceError.invalidAmount
        }

        let terms = try Self.validatedTerms(from: draft)

        let maxInvestors: Int? = {
            let t = draft.maximumInvestors.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let n = Int(t.filter(\.isNumber)), n > 0 else { return nil }
            return n
        }()
        let allowsNegotiation = draft.isNegotiable && (maxInvestors ?? 1) <= 1

        let minimumInvestment = Self.storedMinimumInvestment(amountRequested: amountRequested, maxInvestors: maxInvestors)

        let doc = db.collection("opportunities").document()
        let opportunityID = doc.documentID

        var imageURLs: [String] = []
        var imagePublicIds: [String] = []
        var videoStoragePath: String?
        var videoHTTPSURL: String?
        var videoPublicId: String?
        var mediaWarnings: [String] = []

        for (index, imageData) in imageDataList.enumerated() {
            let payload = ImageJPEGUploadPayload.jpegForUpload(from: imageData)
            let filename = "opportunity-\(opportunityID)-\(index + 1).jpg"
            do {
                try await InappropriateImageGate.validateImageDataForUpload(payload)
                let asset = try await withTimeout(seconds: 60) {
                    try await CloudinaryImageUploadClient.uploadImageData(payload, filename: filename)
                }
                imageURLs.append(asset.secureURL)
                if let pid = asset.publicId {
                    imagePublicIds.append(pid)
                }
            } catch {
                if let le = error as? LocalizedError, error is InappropriateImageGate.GateError {
                    mediaWarnings.append("Image \(index + 1): \(le.errorDescription ?? "Couldn’t add this photo.")")
                } else {
                    mediaWarnings.append("Image \(index + 1) failed to upload.")
                }
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
            "incomeGenerationMethod": normalizedIncomeGeneration,
            "milestones": milestonesPayload,
            "riskLevel": draft.riskLevel.rawValue,
            "verificationStatus": draft.verificationStatus.rawValue,
            "isNegotiable": allowsNegotiation,
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
    ///
    /// Uses a **collection query** by document ID first so Firestore `list` rules apply — the same as market browse.
    /// Many projects allow `list` for open listings but omit `get` for non-owners; a plain `getDocument()` then fails for investors.
    func fetchOpportunity(opportunityId: String) async throws -> OpportunityListing? {
        let trimmed = opportunityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let col = db.collection("opportunities")

        // Strategy 1: direct document read (fast, uses `get` rule)
        do {
            let snapshot = try await col.document(trimmed).getDocument()
            if snapshot.exists, let data = snapshot.data() {
                return OpportunityListing(documentID: trimmed, data: data)
            }
        } catch {
            // `get` may be blocked by rules for non-owners — fall through
        }

        // Strategy 2: collection scan — same query shape as fetchMarketListings, which
        // is known to pass Firestore `list` rules.  Find our document in the results.
        do {
            let snapshot = try await col
                .order(by: "createdAt", descending: true)
                .limit(to: 200)
                .getDocuments()
            if let doc = snapshot.documents.first(where: { $0.documentID == trimmed }) {
                return OpportunityListing(document: doc)
            }
        } catch {
            // ordered query may need an index — try unordered fallback
        }

        // Strategy 3: unordered collection scan (no composite index needed)
        do {
            let snapshot = try await col.limit(to: 300).getDocuments()
            if let doc = snapshot.documents.first(where: { $0.documentID == trimmed }) {
                return OpportunityListing(document: doc)
            }
        } catch {
            throw error
        }

        return nil
    }

    func fetchMarketListings(limit: Int = 50) async throws -> [OpportunityListing] {
        // Fetch extra rows, then drop listings that already have enough active/pending investors
        // (same slot rules as `InvestmentListing.blocksSeekerFromManagingOpportunity` + `maximumInvestors`).
        let fetchCap = min(max(limit * 5, 100), 250)
        let base = db.collection("opportunities")
        let openRows: [OpportunityListing]
        do {
            let snapshot = try await base
                .order(by: "createdAt", descending: true)
                .limit(to: fetchCap)
                .getDocuments()
            openRows = snapshot.documents
                .map { OpportunityListing(document: $0) }
                .filter(\.isOpenForInvesting)
        } catch {
            let snapshot = try await base.limit(to: max(fetchCap, 150)).getDocuments()
            openRows = snapshot.documents
                .map { OpportunityListing(document: $0) }
                .filter(\.isOpenForInvesting)
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
        // Do not call `filterOpenListingsStillAcceptingInvestors` here: it batches `investments` by
        // `opportunityId`, and investors cannot read other parties’ investment docs — Firestore denies the query.
        // Seeker flows that own the listings use `fetchSeekerListingsEligibleForOffers` for slot-aware filtering.
        return Array(openRows.prefix(limit))
    }

    /// Per opportunity, counts investments that still occupy an investor slot (not declined / withdrawn / …).
    private func reservedInvestorSlotCountByOpportunity(opportunityIds: [String]) async throws -> [String: Int] {
        let unique = Array(Set(opportunityIds)).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [:] }
        var counts: [String: Int] = [:]
        var i = unique.startIndex
        while i < unique.endIndex {
            let j = unique.index(i, offsetBy: 10, limitedBy: unique.endIndex) ?? unique.endIndex
            let chunk = Array(unique[i..<j])
            i = j
            let snap = try await db.collection("investments")
                .whereField("opportunityId", in: chunk)
                .getDocuments()
            for doc in snap.documents {
                guard let inv = InvestmentListing(id: doc.documentID, data: doc.data()),
                      let oid = inv.opportunityId, !oid.isEmpty else { continue }
                if inv.blocksSeekerFromManagingOpportunity {
                    counts[oid, default: 0] += 1
                }
            }
        }
        return counts
    }

    private func filterOpenListingsStillAcceptingInvestors(_ rows: [OpportunityListing]) async throws -> [OpportunityListing] {
        guard !rows.isEmpty else { return rows }
        let counts = try await reservedInvestorSlotCountByOpportunity(opportunityIds: rows.map(\.id))
        return rows.filter { opp in
            let cap = max(1, opp.maximumInvestors ?? 1)
            return (counts[opp.id] ?? 0) < cap
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
        let normalizedIncomeGeneration = draft.incomeGenerationMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIncomeGeneration.isEmpty else {
            throw OpportunityServiceError.incomeGenerationRequired
        }

        guard let amountRequested = Self.parseDouble(from: draft.amount), amountRequested > 0 else {
            throw OpportunityServiceError.invalidAmount
        }

        let terms = try Self.validatedTerms(from: draft)

        let maxInvestors: Int? = {
            let t = draft.maximumInvestors.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let n = Int(t.filter(\.isNumber)), n > 0 else { return nil }
            return n
        }()
        let allowsNegotiation = draft.isNegotiable && (maxInvestors ?? 1) <= 1

        let minimumInvestment = Self.storedMinimumInvestment(amountRequested: amountRequested, maxInvestors: maxInvestors)

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
            "incomeGenerationMethod": normalizedIncomeGeneration,
            "milestones": milestonesPayload,
            "riskLevel": draft.riskLevel.rawValue,
            "verificationStatus": draft.verificationStatus.rawValue,
            "isNegotiable": allowsNegotiation,
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

    /// Count of listings this user has created (opportunity builder). Used for profile activity metrics.
    func countOpportunitiesForOwner(ownerId: String) async throws -> Int {
        let snapshot = try await db.collection("opportunities")
            .whereField("ownerId", isEqualTo: ownerId)
            .getDocuments()
        return snapshot.documents.count
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

    /// Open listings from this seeker. With `refineByInvestorCapacity` (default), filters out listings at max
    /// investors via `investments` (seeker-only; requires read access to those rows). Set to `false` when the
    /// caller is an **investor** (e.g. chat “make offer”) — otherwise Firestore denies the batched query.
    func fetchSeekerListingsEligibleForOffers(
        ownerId: String,
        limit: Int = 100,
        refineByInvestorCapacity: Bool = true
    ) async throws -> [OpportunityListing] {
        let rows = try await fetchSeekerListings(ownerId: ownerId, limit: limit)
        let open = rows.filter(\.isOpenForInvesting)
        guard refineByInvestorCapacity else { return open }
        return try await filterOpenListingsStillAcceptingInvestors(open)
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
        sortedMilestoneDraftsForPersistence(items).compactMap { d -> [String: Any]? in
            let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = d.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty && desc.isEmpty { return nil }
            var o: [String: Any] = [
                "title": title.isEmpty ? "Milestone" : title,
                "description": desc
            ]
            let dayDigits = d.daysAfterAcceptance.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
            if let days = Int(dayDigits), days >= 0 {
                o["daysAfterAcceptance"] = min(days, 3650)
            }
            return o
        }
    }

    /// Matches display order: days-after-acceptance ascending; drafts without a day sort last (by title).
    private static func sortedMilestoneDraftsForPersistence(_ items: [MilestoneDraft]) -> [MilestoneDraft] {
        func dayValue(_ d: MilestoneDraft) -> Int? {
            let digits = d.daysAfterAcceptance.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
            guard let n = Int(digits), n >= 0 else { return nil }
            return min(n, 3650)
        }
        return items.sorted { a, b in
            let da = dayValue(a)
            let db = dayValue(b)
            switch (da, db) {
            case let (x?, y?):
                if x != y { return x < y }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
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

    /// Per-investor ticket on the listing: equal split when more than one slot, else the full goal (aligned with `InvestmentService` rounding).
    private static func storedMinimumInvestment(amountRequested: Double, maxInvestors: Int?) -> Double {
        let cap = max(1, maxInvestors ?? 1)
        guard amountRequested > 0 else { return 0 }
        if cap > 1 {
            let raw = amountRequested / Double(cap)
            return (raw * 100).rounded() / 100
        }
        return amountRequested
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
