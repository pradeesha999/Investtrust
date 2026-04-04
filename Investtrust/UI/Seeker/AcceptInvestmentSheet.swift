import SwiftUI

/// Seeker types a verification message; on confirm we accept the request and post it to chat.
struct AcceptInvestmentSheet: View {
    let investment: InvestmentListing
    let opportunity: OpportunityListing
    let onAccept: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var verificationMessage = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This message is sent to the investor in your chat when you accept. Confirm details or add any verification they should know.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Verification message") {
                    TextEditor(text: $verificationMessage)
                        .frame(minHeight: 120)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Accept request")
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
                        Button("Accept & notify") {
                            Task { await submit() }
                        }
                    }
                }
            }
        }
    }

    private func submit() async {
        error = nil
        let trimmed = verificationMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            error = "Please write at least a short verification message (8+ characters)."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onAccept(trimmed)
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
}
