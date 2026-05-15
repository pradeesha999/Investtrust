import FirebaseFirestore
import Foundation

// Firestore deserialisation for InvestmentListing.
// Handles legacy field layouts, numeric type coercions, and nested maps from older document schemas.
extension InvestmentListing {
    init?(id: String, data: [String: Any]) {
        let status = (data["status"] as? String)?.lowercased() ?? "unknown"
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        // Investment amount (Firestore may store numerics as Int / Int64 / Double / NSNumber.)
        let investmentAmount: Double = {
            if let v = Self.parseDouble(data["investmentAmount"]) { return v }
            if let v = Self.parseDouble(data["finalAmount"]) { return v }
            if let v = data["finalTerms"] as? [String: Any], let amount = v["amount"] {
                return Self.parseDouble(amount) ?? 0
            }
            return 0
        }()

        let finalInterestRate: Double? = {
            if let v = Self.parseDouble(data["finalInterestRate"]) { return v }
            if let v = data["finalTerms"] as? [String: Any], let rate = v["interestRate"] {
                return Self.parseDouble(rate)
            }
            return nil
        }()

        let finalTimelineMonths: Int? = {
            if let v = Self.parseInt(data["finalTimelineMonths"]) { return v }
            if let v = data["finalTerms"] as? [String: Any], let timeline = v["timelineMonths"] {
                return Self.parseInt(timeline)
            }
            return nil
        }()

        let investmentType = InvestmentType.parse(
            (data["investmentType"] as? String) ?? (data["opportunityInvestmentType"] as? String)
        )

        let acceptedAt: Date? = {
            if let ts = data["acceptedAt"] as? Timestamp { return ts.dateValue() }
            return nil
        }()

        let receivedAmount: Double = {
            max(0, Self.parseDouble(data["receivedAmount"]) ?? 0)
        }()
        let offerMap = data["offer"] as? [String: Any]
        let requestKind: InvestmentRequestKind = {
            // Prefer explicit offer flags before `requestKind` so Firestore rows stay readable if
            // `requestKind` is stale but `isOfferRequest` / nested `offer.isOffer` are correct.
            if Self.parseBool(data["isOfferRequest"]) == true { return .offer_request }
            if Self.parseBool(offerMap?["isOffer"]) == true { return .offer_request }
            if let raw = data["requestKind"] as? String,
               let kind = InvestmentRequestKind(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return kind
            }
            return .default_request
        }()
        let offerStatus: InvestmentOfferStatus = {
            if let raw = data["offerStatus"] as? String,
               let status = InvestmentOfferStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return status
            }
            if requestKind == .offer_request { return .pending }
            return .pending
        }()
        let offerSource: InvestmentOfferSource? = {
            guard let raw = data["offerSource"] as? String else { return nil }
            return InvestmentOfferSource(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }()
        let offeredAmount: Double? = {
            if let v = data["offeredAmount"] { return Self.parseDouble(v) }
            if let v = offerMap?["amount"] { return Self.parseDouble(v) }
            return nil
        }()
        let offeredInterestRate: Double? = {
            if let v = data["offeredInterestRate"] { return Self.parseDouble(v) }
            if let v = offerMap?["interestRate"] { return Self.parseDouble(v) }
            return nil
        }()
        let offeredTimelineMonths: Int? = {
            if let v = data["offeredTimelineMonths"] { return Self.parseInt(v) }
            if let v = offerMap?["timelineMonths"] { return Self.parseInt(v) }
            return nil
        }()
        let offerDescription = (
            (data["offerDescription"] as? String)
            ?? (offerMap?["description"] as? String)
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let offerChatId = (data["offerChatId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let offerChatMessageId = (data["offerChatMessageId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let agreementStatus: AgreementStatus = {
            if let raw = data["agreementStatus"] as? String,
               let a = AgreementStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return a
            }
            return .none
        }()
        let fundingStatus: FundingStatus = {
            if let raw = data["fundingStatus"] as? String,
               let s = FundingStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return s
            }
            return .none
        }()

        let signedByInvestorAt: Date? = (data["signedByInvestorAt"] as? Timestamp)?.dateValue()
        let signedBySeekerAt: Date? = (data["signedBySeekerAt"] as? Timestamp)?.dateValue()
        let agreementGeneratedAt: Date? = (data["agreementGeneratedAt"] as? Timestamp)?.dateValue()
        let principalSentByInvestorAt: Date? = (data["principalSentByInvestorAt"] as? Timestamp)?.dateValue()
        let principalReceivedBySeekerAt: Date? = (data["principalReceivedBySeekerAt"] as? Timestamp)?.dateValue()
        let principalInvestorProofImageURLs: [String] = data["principalInvestorProofImageURLs"] as? [String] ?? []
        let principalSeekerProofImageURLs: [String] = data["principalSeekerProofImageURLs"] as? [String] ?? []
        let principalSeekerNotReceivedAt: Date? = (data["principalSeekerNotReceivedAt"] as? Timestamp)?.dateValue()
        let principalSeekerNotReceivedReason: String? = {
            let t = (data["principalSeekerNotReceivedReason"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }()

        let agreement: InvestmentAgreementSnapshot? = Self.parseAgreementMap(data["agreement"])

        let loanInstallments: [LoanInstallment] = {
            guard let arr = data["loanInstallments"] as? [[String: Any]] else { return [] }
            return arr.compactMap { LoanInstallment(firestoreMap: $0) }
                .sorted { $0.installmentNo < $1.installmentNo }
        }()
        let revenueSharePeriods: [RevenueSharePeriod] = {
            guard let arr = data["revenueSharePeriods"] as? [[String: Any]] else { return [] }
            return arr.compactMap { RevenueSharePeriod(firestoreMap: $0) }
                .sorted { $0.periodNo < $1.periodNo }
        }()
        let equityMilestones: [EquityMilestoneProgress] = {
            guard let arr = data["equityMilestones"] as? [[String: Any]] else { return [] }
            return arr.compactMap { row in
                let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let description = (row["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty || !description.isEmpty else { return nil }
                let dueDate = (row["dueDate"] as? Timestamp)?.dateValue()
                let updatedAt = (row["updatedAt"] as? Timestamp)?.dateValue()
                let rawStatus = ((row["status"] as? String) ?? "planned")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let status = EquityMilestoneStatus(rawValue: rawStatus) ?? .planned
                let note = (row["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return EquityMilestoneProgress(
                    title: title.isEmpty ? "Milestone" : title,
                    description: description,
                    dueDate: dueDate,
                    status: status,
                    updatedAt: updatedAt,
                    note: note?.isEmpty == false ? note : nil
                )
            }
        }()
        let equityUpdates: [EquityVentureUpdate] = {
            guard let arr = data["equityUpdates"] as? [[String: Any]] else { return [] }
            return arr.compactMap { row in
                let id = (row["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? UUID().uuidString
                let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = (row["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty || !message.isEmpty else { return nil }
                let ventureStage = (row["ventureStage"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let growthMetric = (row["growthMetric"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let attachmentURLs = (row["attachmentURLs"] as? [String] ?? []).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                let createdAt = (row["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                return EquityVentureUpdate(
                    id: id,
                    title: title.isEmpty ? "Venture update" : title,
                    message: message,
                    ventureStage: ventureStage?.isEmpty == false ? ventureStage : nil,
                    growthMetric: growthMetric?.isEmpty == false ? growthMetric : nil,
                    attachmentURLs: attachmentURLs,
                    createdAt: createdAt
                )
            }.sorted { $0.createdAt > $1.createdAt }
        }()

        let moaPdfURL = (data["moaPdfURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let moaContentHash = (data["moaContentHash"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let investorSignatureImageURL = (data["investorSignatureImageURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let seekerSignatureImageURL = (data["seekerSignatureImageURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Title + thumbnail: prefer `thumbnailImageURL` (new), then nested `opportunity`, then legacy `imageURLs` array.
        var opportunityTitle = ""
        var imageURLs: [String] = []

        if let thumb = data["thumbnailImageURL"] as? String {
            let t = thumb.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { imageURLs = [t] }
        }

        if let opportunity = data["opportunity"] as? [String: Any] {
            if opportunityTitle.isEmpty {
                opportunityTitle = (opportunity["title"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            if imageURLs.isEmpty {
                imageURLs = (opportunity["imageURLs"] as? [String] ?? [])
            }
        }

        if opportunityTitle.isEmpty {
            opportunityTitle = (data["opportunityTitle"] as? String) ?? ""
        }
        if imageURLs.isEmpty, let direct = data["imageURLs"] as? [String] {
            imageURLs = direct
        }

        var opportunityId = Self.parseOpportunityIdField(data["opportunityId"])
        if opportunityId.isEmpty, let opportunity = data["opportunity"] as? [String: Any] {
            if let oid = opportunity["id"] as? String {
                opportunityId = oid.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let ref = opportunity["id"] as? DocumentReference {
                opportunityId = ref.documentID
            }
        }

        let rawInvestor = (data["investorId"] as? String) ?? (data["investor"] as? String)
        let trimmedInvestor = rawInvestor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var seeker = (data["seekerId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if seeker.isEmpty, let opportunity = data["opportunity"] as? [String: Any],
           let oid = opportunity["ownerId"] as? String {
            seeker = oid.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        self.init(
            id: id,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            opportunityId: opportunityId.isEmpty ? nil : opportunityId,
            investorId: trimmedInvestor.isEmpty ? nil : trimmedInvestor,
            seekerId: seeker.isEmpty ? nil : seeker,
            opportunityTitle: opportunityTitle,
            imageURLs: imageURLs,
            investmentAmount: investmentAmount,
            finalInterestRate: finalInterestRate,
            finalTimelineMonths: finalTimelineMonths,
            investmentType: investmentType,
            acceptedAt: acceptedAt,
            receivedAmount: receivedAmount,
            requestKind: requestKind,
            offerStatus: offerStatus,
            offerSource: offerSource,
            offeredAmount: offeredAmount,
            offeredInterestRate: offeredInterestRate,
            offeredTimelineMonths: offeredTimelineMonths,
            offerDescription: offerDescription?.isEmpty == false ? offerDescription : nil,
            offerChatId: offerChatId?.isEmpty == false ? offerChatId : nil,
            offerChatMessageId: offerChatMessageId?.isEmpty == false ? offerChatMessageId : nil,
            agreementStatus: agreementStatus,
            fundingStatus: fundingStatus,
            signedByInvestorAt: signedByInvestorAt,
            signedBySeekerAt: signedBySeekerAt,
            agreementGeneratedAt: agreementGeneratedAt,
            agreement: agreement,
            loanInstallments: loanInstallments,
            revenueSharePeriods: revenueSharePeriods,
            moaPdfURL: moaPdfURL?.isEmpty == false ? moaPdfURL : nil,
            moaContentHash: moaContentHash?.isEmpty == false ? moaContentHash : nil,
            investorSignatureImageURL: investorSignatureImageURL?.isEmpty == false ? investorSignatureImageURL : nil,
            seekerSignatureImageURL: seekerSignatureImageURL?.isEmpty == false ? seekerSignatureImageURL : nil,
            principalSentByInvestorAt: principalSentByInvestorAt,
            principalReceivedBySeekerAt: principalReceivedBySeekerAt,
            principalInvestorProofImageURLs: principalInvestorProofImageURLs,
            principalSeekerProofImageURLs: principalSeekerProofImageURLs,
            principalSeekerNotReceivedAt: principalSeekerNotReceivedAt,
            principalSeekerNotReceivedReason: principalSeekerNotReceivedReason,
            equityMilestones: equityMilestones,
            equityUpdates: equityUpdates
        )
    }

    private static func parseOpportunityIdField(_ raw: Any?) -> String {
        if let s = raw as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ref = raw as? DocumentReference {
            return ref.documentID
        }
        return ""
    }

    private static func parseAgreementMap(_ raw: Any?) -> InvestmentAgreementSnapshot? {
        guard let m = raw as? [String: Any], !m.isEmpty else { return nil }
        let agreementId = (m["agreementId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let agreementVersion: Int = {
            if let v = m["agreementVersion"] as? Int { return v }
            if let n = m["agreementVersion"] as? NSNumber { return n.intValue }
            return 1
        }()
        let termsSnapshotHash = (m["termsSnapshotHash"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var requiredSignerIds: [String] = (m["requiredSignerIds"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let participants: [AgreementSignerSnapshot] = {
            guard let rows = m["participants"] as? [[String: Any]] else { return [] }
            return rows.compactMap { row in
                let signerId = (row["signerId"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !signerId.isEmpty else { return nil }
                let role = AgreementSignerRole(
                    rawValue: ((row["signerRole"] as? String) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                ) ?? .investor
                let displayName = (row["displayName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let signatureURL = (row["signatureURL"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let signedAt = (row["signedAt"] as? Timestamp)?.dateValue()
                return AgreementSignerSnapshot(
                    signerId: signerId,
                    signerRole: role,
                    displayName: displayName.isEmpty ? "Signer" : displayName,
                    signatureURL: signatureURL?.isEmpty == false ? signatureURL : nil,
                    signedAt: signedAt
                )
            }
        }()
        if requiredSignerIds.isEmpty, !participants.isEmpty {
            requiredSignerIds = participants.map(\.signerId)
        }
        let linkedInvestmentIds: [String] = (m["linkedInvestmentIds"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = (m["opportunityTitle"] as? String) ?? ""
        let investorName = (m["investorName"] as? String) ?? ""
        let seekerName = (m["seekerName"] as? String) ?? ""
        let amount = parseDouble(m["investmentAmount"]) ?? 0
        let type = InvestmentType.parse(m["investmentType"] as? String)
        let termsMap = (m["termsSnapshot"] as? [String: Any]) ?? [:]
        let wrap: [String: Any] = ["terms": termsMap]
        let terms = OpportunityFirestoreCoding.parseTerms(from: wrap, type: type)
        let createdAt: Date = {
            if let ts = m["createdAt"] as? Timestamp { return ts.dateValue() }
            return Date()
        }()
        return InvestmentAgreementSnapshot(
            agreementId: agreementId,
            agreementVersion: max(1, agreementVersion),
            termsSnapshotHash: termsSnapshotHash,
            requiredSignerIds: requiredSignerIds,
            linkedInvestmentIds: linkedInvestmentIds,
            participants: participants,
            opportunityTitle: title,
            investorName: investorName,
            seekerName: seekerName,
            investmentAmount: amount,
            investmentType: type,
            termsSnapshot: terms,
            createdAt: createdAt
        )
    }

    private static func parseBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let i = value as? Int { return i != 0 }
        return nil
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let v = value as? Double { return v }
        if let n = value as? NSNumber { return n.doubleValue }
        if let v = value as? Int { return Double(v) }
        if let v = value as? Int64 { return Double(v) }
        if let s = value as? String {
            let cleaned = s.replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }
        return nil
    }

    private static func parseInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String {
            let digits = s.filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }
}
