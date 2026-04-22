import FirebaseFirestore
import Foundation

extension InvestmentListing {
    init?(id: String, data: [String: Any]) {
        let status = (data["status"] as? String)?.lowercased() ?? "unknown"
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

        // Investment amount
        let investmentAmount: Double = {
            if let v = data["investmentAmount"] as? Double { return v }
            if let n = data["investmentAmount"] as? NSNumber { return n.doubleValue }
            if let v = data["finalAmount"] as? Double { return v }
            if let n = data["finalAmount"] as? NSNumber { return n.doubleValue }
            if let v = data["finalTerms"] as? [String: Any], let amount = v["amount"] {
                return Self.parseDouble(amount) ?? 0
            }
            return 0
        }()

        let finalInterestRate: Double? = {
            if let v = data["finalInterestRate"] as? Double { return v }
            if let n = data["finalInterestRate"] as? NSNumber { return n.doubleValue }
            if let v = data["finalTerms"] as? [String: Any], let rate = v["interestRate"] {
                return Self.parseDouble(rate)
            }
            return nil
        }()

        let finalTimelineMonths: Int? = {
            if let v = data["finalTimelineMonths"] as? Int { return v }
            if let n = data["finalTimelineMonths"] as? NSNumber { return n.intValue }
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
            if let v = data["receivedAmount"] as? Double { return max(0, v) }
            if let n = data["receivedAmount"] as? NSNumber { return max(0, n.doubleValue) }
            return 0
        }()

        let agreementStatus: AgreementStatus = {
            if let raw = data["agreementStatus"] as? String,
               let a = AgreementStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return a
            }
            return .none
        }()

        let signedByInvestorAt: Date? = (data["signedByInvestorAt"] as? Timestamp)?.dateValue()
        let signedBySeekerAt: Date? = (data["signedBySeekerAt"] as? Timestamp)?.dateValue()
        let agreementGeneratedAt: Date? = (data["agreementGeneratedAt"] as? Timestamp)?.dateValue()

        let agreement: InvestmentAgreementSnapshot? = Self.parseAgreementMap(data["agreement"])

        let loanInstallments: [LoanInstallment] = {
            guard let arr = data["loanInstallments"] as? [[String: Any]] else { return [] }
            return arr.compactMap { LoanInstallment(firestoreMap: $0) }
                .sorted { $0.installmentNo < $1.installmentNo }
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
            agreementStatus: agreementStatus,
            signedByInvestorAt: signedByInvestorAt,
            signedBySeekerAt: signedBySeekerAt,
            agreementGeneratedAt: agreementGeneratedAt,
            agreement: agreement,
            loanInstallments: loanInstallments,
            moaPdfURL: moaPdfURL?.isEmpty == false ? moaPdfURL : nil,
            moaContentHash: moaContentHash?.isEmpty == false ? moaContentHash : nil,
            investorSignatureImageURL: investorSignatureImageURL?.isEmpty == false ? investorSignatureImageURL : nil,
            seekerSignatureImageURL: seekerSignatureImageURL?.isEmpty == false ? seekerSignatureImageURL : nil
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
            opportunityTitle: title,
            investorName: investorName,
            seekerName: seekerName,
            investmentAmount: amount,
            investmentType: type,
            termsSnapshot: terms,
            createdAt: createdAt
        )
    }

    private static func parseDouble(_ value: Any) -> Double? {
        if let v = value as? Double { return v }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String {
            let cleaned = s.replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }
        return nil
    }

    private static func parseInt(_ value: Any) -> Int? {
        if let v = value as? Int { return v }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String {
            let digits = s.filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }
}
