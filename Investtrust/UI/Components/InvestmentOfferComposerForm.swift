import SwiftUI

/// Shared fields for sending a negotiated investment offer (chat or opportunity detail).
struct InvestmentOfferComposerForm: View {
    let opportunities: [OpportunityListing]
    @Binding var selectedOpportunityId: String
    let showOpportunityPicker: Bool
    /// Shown when `opportunities` is empty (e.g. chat-specific hint).
    let emptyListingMessage: String?
    @Binding var amountText: String
    @Binding var rateText: String
    @Binding var timelineText: String
    @Binding var descriptionText: String
    let errorText: String?

    private var selected: OpportunityListing? {
        let id = selectedOpportunityId.isEmpty ? (opportunities.first?.id ?? "") : selectedOpportunityId
        guard !id.isEmpty else { return nil }
        return opportunities.first { $0.id == id }
    }

    var body: some View {
        Form {
            if opportunities.isEmpty {
                Text(emptyListingMessage ?? "No opportunities available for offers here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if showOpportunityPicker {
                    Section("Opportunity") {
                        Picker("Select opportunity", selection: $selectedOpportunityId) {
                            ForEach(opportunities) { opp in
                                Text(opp.title).tag(opp.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                if let selected {
                    let cap = max(1, selected.maximumInvestors ?? 1)
                    let fixedAmount = Self.offerAmountForOpportunity(selected)
                    let multi = cap > 1
                    Section("Offer terms") {
                        if multi {
                            LabeledContent("Amount") {
                                Text(Self.lkr(fixedAmount))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Fixed equal split for \(cap) investors.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("Amount (LKR)", text: $amountText)
                                .keyboardType(.decimalPad)
                        }
                        TextField("Interest rate (%)", text: $rateText)
                            .keyboardType(.decimalPad)
                        TextField("Repayment timeline (months)", text: $timelineText)
                            .keyboardType(.numberPad)
                        TextField("Description", text: $descriptionText, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
            }

            if let errorText, !errorText.isEmpty {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    static func offerAmountForOpportunity(_ opportunity: OpportunityListing) -> Double {
        let cap = max(1, opportunity.maximumInvestors ?? 1)
        if cap <= 1 { return opportunity.amountRequested }
        let raw = opportunity.amountRequested / Double(cap)
        return (raw * 100).rounded() / 100
    }

    static func lkr(_ value: Double) -> String {
        let number = NSNumber(value: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return "LKR \(formatter.string(from: number) ?? String(format: "%.2f", value))"
    }
}
