import Foundation

struct OpportunityListing: Identifiable, Equatable, Hashable {
    let id: String
    let ownerId: String
    let title: String
    let category: String
    let description: String
    let amountRequested: Double
    let interestRate: Double
    let repaymentTimelineMonths: Int
    let status: String
    let createdAt: Date?
    let imageStoragePaths: [String]
    let videoStoragePath: String?

    var formattedAmountLKR: String {
        let n = NSNumber(value: amountRequested)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", amountRequested)
    }

    var repaymentLabel: String {
        "\(repaymentTimelineMonths) months"
    }
}
