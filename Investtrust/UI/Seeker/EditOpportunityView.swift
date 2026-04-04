//
//  EditOpportunityView.swift
//  Investtrust
//

import SwiftUI

/// Text/terms edit for an existing listing (images and video stay as uploaded).
struct EditOpportunityView: View {
    @Environment(\.dismiss) private var dismiss

    let opportunity: OpportunityListing
    @State private var draft: OpportunityDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    var onSave: (OpportunityDraft) async throws -> Void

    init(opportunity: OpportunityListing, onSave: @escaping (OpportunityDraft) async throws -> Void) {
        self.opportunity = opportunity
        self.onSave = onSave
        _draft = State(initialValue: Self.draft(from: opportunity))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Photos and video can’t be changed here yet. Update title, terms, and description below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    field("Opportunity title", text: $draft.title, placeholder: "Title")
                    field("Category", text: $draft.category, placeholder: "Category")
                    field("Amount needed (LKR)", text: $draft.amount, placeholder: "150000", keyboardType: .numberPad)
                    field("Interest rate (%)", text: $draft.interestRate, placeholder: "12", keyboardType: .decimalPad)
                    field("Repayment timeline", text: $draft.repaymentTimeline, placeholder: "12 months")

                    textArea("Description", text: $draft.description, placeholder: "Describe the opportunity.")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "Saving…" : "Save changes")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                    .disabled(!canSave || isSaving)
                    .opacity(canSave && !isSaving ? 1 : 0.45)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.amount.isEmpty
            && !draft.interestRate.isEmpty
            && !draft.repaymentTimeline.isEmpty
            && !draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            if let le = error as? LocalizedError, let d = le.errorDescription {
                errorMessage = d
            } else {
                errorMessage = (error as NSError).localizedDescription
            }
        }
    }

    private static func draft(from listing: OpportunityListing) -> OpportunityDraft {
        var d = OpportunityDraft()
        d.title = listing.title
        d.category = listing.category
        d.amount = String(format: "%.0f", listing.amountRequested)
        if listing.interestRate == floor(listing.interestRate) {
            d.interestRate = String(Int(listing.interestRate))
        } else {
            d.interestRate = String(listing.interestRate)
        }
        d.repaymentTimeline = "\(listing.repaymentTimelineMonths) months"
        d.description = listing.description
        return d
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1.5)
                )
        }
    }

    private func textArea(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .frame(height: 140)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1.5)
            )
        }
    }
}
