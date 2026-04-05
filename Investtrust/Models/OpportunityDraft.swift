import Foundation

struct MilestoneDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var expectedDate: Date?

    init(id: UUID = UUID(), title: String = "", description: String = "", expectedDate: Date? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.expectedDate = expectedDate
    }
}

struct OpportunityDraft: Identifiable, Equatable {
    let id = UUID()

    var investmentType: InvestmentType = .loan

    var title: String = ""
    var category: String = ""
    var description: String = ""
    var location: String = ""

    var amount: String = ""
    var minimumInvestment: String = ""
    var maximumInvestors: String = ""

    var riskLevel: RiskLevel = .medium
    var verificationStatus: VerificationStatus = .unverified
    var useOfFunds: String = ""
    var milestones: [MilestoneDraft] = []

    // Loan
    var interestRate: String = ""
    var repaymentTimeline: String = ""
    var repaymentFrequency: RepaymentFrequency = .monthly

    // Equity
    var equityPercentage: String = ""
    var businessValuation: String = ""
    var exitPlan: String = ""

    // Revenue share
    var revenueSharePercent: String = ""
    var targetReturnAmount: String = ""
    var maxDurationMonths: String = ""

    // Project
    var expectedReturnType: ExpectedReturnType = .fixed
    var expectedReturnValue: String = ""
    var completionDate: Date?

    // Custom
    var customTermsSummary: String = ""
}
