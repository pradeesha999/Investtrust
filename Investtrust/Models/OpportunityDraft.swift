import Foundation

struct MilestoneDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String
    /// Days after investment acceptance (digits only in UI).
    var daysAfterAcceptance: String

    init(id: UUID = UUID(), title: String = "", description: String = "", daysAfterAcceptance: String = "") {
        self.id = id
        self.title = title
        self.description = description
        self.daysAfterAcceptance = daysAfterAcceptance
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
    var maximumInvestors: String = ""

    var riskLevel: RiskLevel = .medium
    var verificationStatus: VerificationStatus = .unverified
    var isNegotiable: Bool = true
    var useOfFunds: String = ""
    var incomeGenerationMethod: String = ""
    var milestones: [MilestoneDraft] = []

    // Loan
    var interestRate: String = ""
    var repaymentTimeline: String = ""
    var repaymentFrequency: RepaymentFrequency = .monthly

    // Equity
    var equityPercentage: String = ""
    var businessValuation: String = ""
    var equityTimelineMonths: String = ""
    var ventureName: String = ""
    var ventureStage: VentureStage = .idea_stage
    var futureGoals: String = ""
    var revenueModel: String = ""
    var targetAudience: String = ""
    var demoLinks: String = ""
    var equityRoiTimeline: EquityRoiTimeline = .one_year
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
