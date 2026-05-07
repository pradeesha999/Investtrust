import SwiftUI

/// Confirms a standard investment request on the listing’s stated terms (no custom amount or checkboxes here—MOA covers legal acceptance).
struct InvestProposalSheet: View {
    enum Submission {
        case standardRequest
        case negotiatedOffer(amount: Double?, interestRate: Double, timelineMonths: Int, note: String)
    }

    let opportunity: OpportunityListing
    let onSubmit: (Submission) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var confirmStandardRequest = false
    @State private var offerAmountText = ""
    @State private var offerRateText = ""
    @State private var offerTimelineText = ""
    @State private var offerNote = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(introCopy)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if opportunity.isNegotiable {
                    Section("Negotiated terms") {
                        if max(1, opportunity.maximumInvestors ?? 1) <= 1 {
                            TextField("Amount (LKR)", text: $offerAmountText)
                                .keyboardType(.numberPad)
                        } else {
                            Text("Amount is fixed by investor split for this listing.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Interest rate (%)", text: $offerRateText)
                            .keyboardType(.decimalPad)
                        TextField("Timeline (months)", text: $offerTimelineText)
                            .keyboardType(.numberPad)
                        TextField("Notes (optional)", text: $offerNote, axis: .vertical)
                            .lineLimit(1...3)
                    }
                } else {
                    Section {
                        Toggle("I confirm I want to send a request on listed terms.", isOn: $confirmStandardRequest)
                    }
                }

                if let submitError {
                    Section {
                        Text(submitError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Investment request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(opportunity.isNegotiable ? "Send offer request" : "Send request") {
                            Task { await submit() }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
        }
        .onAppear {
            let cap = max(1, opportunity.maximumInvestors ?? 1)
            if cap <= 1 {
                offerAmountText = Self.formatLKR(opportunity.amountRequested)
            }
            offerRateText = opportunity.interestRate > 0 ? String(format: "%.2f", opportunity.interestRate) : ""
            offerTimelineText = "\(max(1, opportunity.repaymentTimelineMonths))"
        }
    }

    private var introCopy: String {
        let cap = max(1, opportunity.maximumInvestors ?? 1)
        if cap > 1 {
            let split = InvestmentService.fixedEqualSplitAmount(
                total: opportunity.amountRequested,
                investors: cap
            )
            let splitText = Self.formatLKR(split)
            return "You’re requesting to invest on this listing’s stated terms: \(opportunity.investmentType.displayName) — \(opportunity.termsSummaryLine). With \(cap) investors, each ticket is LKR \(splitText). The seeker can accept or decline. You’ll review and sign the memorandum of agreement if they accept."
        }
        let amt = Self.formatLKR(opportunity.amountRequested)
        return "You’re requesting to invest LKR \(amt) on this listing’s stated terms: \(opportunity.investmentType.displayName) — \(opportunity.termsSummaryLine). The seeker can accept or decline. You’ll review and sign the memorandum of agreement if they accept."
    }

    private static func formatLKR(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }

    private var canSubmit: Bool {
        if opportunity.isNegotiable {
            guard let _ = parsedInterestRate, let _ = parsedTimelineMonths else { return false }
            let cap = max(1, opportunity.maximumInvestors ?? 1)
            if cap <= 1 {
                return parsedAmount != nil
            }
            return true
        }
        return confirmStandardRequest
    }

    private var parsedAmount: Double? {
        let cap = max(1, opportunity.maximumInvestors ?? 1)
        guard cap <= 1 else { return nil }
        let cleaned = offerAmountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var parsedInterestRate: Double? {
        let cleaned = offerRateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var parsedTimelineMonths: Int? {
        let digits = offerTimelineText.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private func submit() async {
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if opportunity.isNegotiable {
                guard let rate = parsedInterestRate, let timeline = parsedTimelineMonths else {
                    submitError = "Enter valid offer terms (rate and timeline)."
                    return
                }
                let cap = max(1, opportunity.maximumInvestors ?? 1)
                let amount = cap <= 1 ? parsedAmount : nil
                if cap <= 1, amount == nil {
                    submitError = "Enter a valid amount."
                    return
                }
                try await onSubmit(.negotiatedOffer(
                    amount: amount,
                    interestRate: rate,
                    timelineMonths: timeline,
                    note: offerNote.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            } else {
                guard confirmStandardRequest else {
                    submitError = "Please confirm before sending the request."
                    return
                }
                try await onSubmit(.standardRequest)
            }
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                if let le = error as? LocalizedError, let d = le.errorDescription {
                    submitError = d
                } else {
                    submitError = (error as NSError).localizedDescription
                }
            }
        }
    }
}
