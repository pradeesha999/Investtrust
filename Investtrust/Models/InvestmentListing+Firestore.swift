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
        
        // Opportunity title + media
        var opportunityTitle = ""
        var imageURLs: [String] = []
        
        if let opportunity = data["opportunity"] as? [String: Any] {
            opportunityTitle = (opportunity["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            imageURLs = (opportunity["imageURLs"] as? [String] ?? [])
        }
        
        // Fallbacks if media/title are stored directly
        if opportunityTitle.isEmpty {
            opportunityTitle = (data["opportunityTitle"] as? String) ?? ""
        }
        if imageURLs.isEmpty, let direct = data["imageURLs"] as? [String] {
            imageURLs = direct
        }
        
        self.init(
            id: id,
            status: status,
            createdAt: createdAt,
            opportunityTitle: opportunityTitle,
            imageURLs: imageURLs,
            investmentAmount: investmentAmount,
            finalInterestRate: finalInterestRate,
            finalTimelineMonths: finalTimelineMonths
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

