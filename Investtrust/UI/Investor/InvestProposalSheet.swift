import SwiftUI

/// Confirms a standard investment request on the listing’s stated terms (no custom amount or checkboxes here—MOA covers legal acceptance).
struct InvestProposalSheet: View {
    let opportunity: OpportunityListing
    let onSubmit: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(introCopy)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        Button("Send request") {
                            Task { await submit() }
                        }
                    }
                }
            }
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

    private func submit() async {
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onSubmit()
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
