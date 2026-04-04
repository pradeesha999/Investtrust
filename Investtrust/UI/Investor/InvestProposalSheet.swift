import SwiftUI

/// Confirms proposed amount and submits a pending investment request.
struct InvestProposalSheet: View {
    let opportunity: OpportunityListing
    let onSubmit: (Double) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You’re requesting to invest on the listing’s stated terms (interest \(formatRate(opportunity.interestRate))%, \(opportunity.repaymentLabel)). The seeker can accept or decline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Proposed amount (LKR)") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                }

                if let error {
                    Section {
                        Text(error)
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
        error = nil
        let cleaned = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0 else {
            error = "Enter a valid amount."
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
                    error = d
                } else {
                    error = (error as NSError).localizedDescription
                }
            }
        }
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) { return String(Int(rate)) }
        return String(rate)
    }
}
