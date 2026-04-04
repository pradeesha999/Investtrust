import Foundation

struct InvestmentListing: Identifiable, Equatable {
    let id: String
    let status: String
    let createdAt: Date?
    
    let opportunityTitle: String
    let imageURLs: [String]
    
    let investmentAmount: Double
    let finalInterestRate: Double?
    let finalTimelineMonths: Int?
    
    var interestLabel: String {
        guard let finalInterestRate else { return "-" }
        return "\(finalInterestRate)%"
    }
    
    var timelineLabel: String {
        guard let finalTimelineMonths else { return "-" }
        return "\(finalTimelineMonths) months"
    }
}

