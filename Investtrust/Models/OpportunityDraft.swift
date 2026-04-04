import Foundation

struct OpportunityDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String = ""
    var category: String = ""
    var amount: String = ""
    var interestRate: String = ""
    var repaymentTimeline: String = ""
    var description: String = ""
}
