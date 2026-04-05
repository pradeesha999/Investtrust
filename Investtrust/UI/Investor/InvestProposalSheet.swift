import SwiftUI

/// Confirms proposed amount and submits a pending investment request.
struct InvestProposalSheet: View {
    let opportunity: OpportunityListing
    let onSubmit: (Double) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var acknowledgesOffPlatform = false
    @State private var agreesToTerms = false
    @State private var isSubmitting = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "You’re requesting to invest on this listing’s stated terms: \(opportunity.investmentType.displayName) — \(opportunity.termsSummaryLine). Minimum ticket LKR \(opportunity.formattedMinimumLKR). The seeker can accept or decline."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Proposed amount (LKR)") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                }

                Section {
                    Toggle("I understand this investment happens outside the platform", isOn: $acknowledgesOffPlatform)
                    Toggle("I agree to the opportunity terms", isOn: $agreesToTerms)
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
                        Button("Send") {
                            Task { await submit() }
                        }
                        .disabled(!acknowledgesOffPlatform || !agreesToTerms)
                    }
                }
            }
            .onAppear {
                if amountText.isEmpty {
                    let n = NSNumber(value: opportunity.amountRequested)
                    let f = NumberFormatter()
                    f.numberStyle = .decimal
                    f.maximumFractionDigits = 0
                    amountText = f.string(from: n) ?? String(format: "%.0f", opportunity.amountRequested)
                }
            }
        }
    }

    private func submit() async {
        submitError = nil
        guard acknowledgesOffPlatform, agreesToTerms else {
            submitError = "Confirm both acknowledgements to continue."
            return
        }
        let cleaned = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0 else {
            submitError = "Enter a valid amount."
            return
        }
        guard value >= opportunity.minimumInvestment else {
            submitError = "Amount must be at least LKR \(opportunity.formattedMinimumLKR)."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onSubmit(value)
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
