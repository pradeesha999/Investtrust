import Foundation

struct ChatThread: Identifiable, Equatable {
    let id: String
    let seekerId: String?
    let investorId: String?
    /// Legacy Firestore field (opportunity title); UI prefers counterparty profile.
    let title: String
    let lastMessagePreview: String
    let lastMessageAt: Date?

    func counterpartyId(currentUserId: String?) -> String? {
        guard let currentUserId else { return nil }
        if seekerId == currentUserId { return investorId }
        if investorId == currentUserId { return seekerId }
        return investorId ?? seekerId
    }
}

struct OpportunityInquirySnapshot: Equatable, Hashable {
    let opportunityId: String
    let title: String
    let investmentTypeLabel: String
    let fundingGoalText: String
    let minTicketText: String
    let termsSummary: String
    let timelineText: String
}

struct InvestmentRequestSnapshot: Equatable, Hashable {
    let investmentId: String?
    let opportunityId: String
    let title: String
    let amountText: String
    let interestRateText: String
    let timelineText: String
    let note: String
    let requestKindLabel: String
}

struct InvestmentOfferSnapshot: Equatable, Hashable {
    let investmentId: String?
    let opportunityId: String
    let title: String
    let amountText: String
    let interestRateText: String
    let timelineText: String
    let description: String
    let isFixedAmount: Bool
}

struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case text
        case opportunityInquiry(snapshot: OpportunityInquirySnapshot)
        case investmentRequest(snapshot: InvestmentRequestSnapshot)
        case investmentOffer(snapshot: InvestmentOfferSnapshot)
    }

    let id: String
    let senderId: String
    let text: String
    let createdAt: Date?
    let kind: Kind
}
