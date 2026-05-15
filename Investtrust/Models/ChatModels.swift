import Foundation

// A conversation between one investor and one seeker, tied to a deal.
// Chat threads appear on the Chat tab and can be opened from deal detail screens.
struct ChatThread: Identifiable, Equatable {
    let id: String
    let seekerId: String?
    let investorId: String?
    let title: String           // opportunity name — used as a fallback thread label
    let lastMessagePreview: String
    let lastMessageAt: Date?

    // Returns the other person's user ID so the UI can load their avatar and name
    func counterpartyId(currentUserId: String?) -> String? {
        guard let currentUserId else { return nil }
        if seekerId == currentUserId { return investorId }
        if investorId == currentUserId { return seekerId }
        return investorId ?? seekerId
    }
}

// Summary card shown inside a chat message when a user shares an opportunity listing
struct OpportunityInquirySnapshot: Equatable, Hashable {
    let opportunityId: String
    let title: String
    let investmentTypeLabel: String
    let fundingGoalText: String
    let minTicketText: String
    let termsSummary: String
    let timelineText: String
}

// Summary card shown inside a chat message when an investor sends a default investment request
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

// Summary card shown inside a chat message when an investor sends a custom counter-offer
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

// A single message in a chat thread; kind determines how the bubble is rendered
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
