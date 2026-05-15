import Foundation

// A single milestone row in the Create Opportunity wizard (equity deals only).
// Seekers add milestones to show investors what they plan to achieve and by when.
struct MilestoneDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var daysAfterAcceptance: String  // entered as digits; converted to Int before saving

    init(id: UUID = UUID(), title: String = "", description: String = "", daysAfterAcceptance: String = "") {
        self.id = id
        self.title = title
        self.description = description
        self.daysAfterAcceptance = daysAfterAcceptance
    }
}

// In-memory working copy while the seeker fills in the Create Opportunity wizard.
// Converted to an OpportunityListing when the seeker publishes.
struct OpportunityDraft: Identifiable, Equatable {
    let id = UUID()

    var investmentType: InvestmentType = .loan  // determines which wizard pages are shown

    // Basic listing info
    var title: String = ""
    var category: String = ""
    var description: String = ""
    var location: String = ""

    var amount: String = ""           // funding goal in LKR
    var maximumInvestors: String = "" // how many investors can participate

    var riskLevel: RiskLevel = .medium
    var verificationStatus: VerificationStatus = .unverified
    var isNegotiable: Bool = true
    var useOfFunds: String = ""
    var incomeGenerationMethod: String = ""
    var milestones: [MilestoneDraft] = []

    // Loan-specific fields
    var interestRate: String = ""
    var repaymentTimeline: String = ""
    var repaymentFrequency: RepaymentFrequency = .monthly

    // Equity-specific fields
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

    // Revenue share fields
    var revenueSharePercent: String = ""
    var targetReturnAmount: String = ""
    var maxDurationMonths: String = ""

    // Project investment fields
    var expectedReturnType: ExpectedReturnType = .fixed
    var expectedReturnValue: String = ""
    var completionDate: Date?

    // Custom / free-form deal fields
    var customTermsSummary: String = ""
}
