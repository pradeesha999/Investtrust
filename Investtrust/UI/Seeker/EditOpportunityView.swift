//
//  EditOpportunityView.swift
//  Investtrust
//

import SwiftUI

/// Edit text, terms, and execution fields for an existing listing (images and video stay as uploaded).
struct EditOpportunityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                    Text("Photos and video can’t be changed here yet. Update everything else below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(AppTheme.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))

                    formSection("Investment type") {
                        Picker("Type", selection: $draft.investmentType) {
                            ForEach(InvestmentType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    formSection("Basics") {
                        field("Opportunity title", text: $draft.title, placeholder: "Title")
                        field("Category", text: $draft.category, placeholder: "Category")
                        textArea("Description", text: $draft.description, placeholder: "Describe the opportunity.")
                    }

                    formSection("Funding & risk") {
                        field("Amount needed (LKR)", text: $draft.amount, placeholder: "150000", keyboardType: .numberPad)
                        field("Minimum investment (LKR)", text: $draft.minimumInvestment, placeholder: "Leave blank to auto")
                        field("Maximum investors (optional)", text: $draft.maximumInvestors, placeholder: "e.g. 20")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Risk level")
                                .font(.subheadline.weight(.semibold))
                            Picker("Risk", selection: $draft.riskLevel) {
                                ForEach([RiskLevel.low, .medium, .high], id: \.self) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        field("Location", text: $draft.location, placeholder: "City / region")
                    }

                    formSection("Terms — \(draft.investmentType.displayName)") {
                        Group {
                            switch draft.investmentType {
                            case .loan:
                                field("Interest rate (%)", text: $draft.interestRate, placeholder: "12", keyboardType: .decimalPad)
                                field("Repayment timeline (months)", text: $draft.repaymentTimeline, placeholder: "12")
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Repayment frequency")
                                        .font(.subheadline.weight(.semibold))
                                    Picker("Frequency", selection: $draft.repaymentFrequency) {
                                        Text("Monthly").tag(RepaymentFrequency.monthly)
                                        Text("Weekly").tag(RepaymentFrequency.weekly)
                                        Text("One-time at maturity").tag(RepaymentFrequency.one_time)
                                    }
                                    .pickerStyle(.menu)
                                }
                            case .equity:
                                field("Equity offered (%)", text: $draft.equityPercentage, placeholder: "10", keyboardType: .decimalPad)
                                field("Business valuation (LKR, optional)", text: $draft.businessValuation, placeholder: "5000000", keyboardType: .numberPad)
                                textArea("Exit plan", text: $draft.exitPlan, placeholder: "How investors may realize returns.")
                            case .revenue_share:
                                field("Revenue share (%)", text: $draft.revenueSharePercent, placeholder: "5", keyboardType: .decimalPad)
                                field("Target return amount (LKR)", text: $draft.targetReturnAmount, placeholder: "500000", keyboardType: .numberPad)
                                field("Maximum duration (months)", text: $draft.maxDurationMonths, placeholder: "24")
                            case .project:
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Expected return type")
                                        .font(.subheadline.weight(.semibold))
                                    Picker("Return type", selection: $draft.expectedReturnType) {
                                        Text("Fixed").tag(ExpectedReturnType.fixed)
                                        Text("Product").tag(ExpectedReturnType.product)
                                        Text("None").tag(ExpectedReturnType.none)
                                    }
                                    .pickerStyle(.segmented)
                                }
                                field("Expected return (describe)", text: $draft.expectedReturnValue, placeholder: "Describe the return")
                                DatePicker(
                                    "Target completion date",
                                    selection: Binding(
                                        get: { draft.completionDate ?? Date() },
                                        set: { draft.completionDate = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                            case .custom:
                                textArea("Custom terms summary", text: $draft.customTermsSummary, placeholder: "Plain-language deal terms.")
                            }
                        }
                    }

                    formSection("Execution plan") {
                        textArea("Use of funds", text: $draft.useOfFunds, placeholder: "What the money will be spent on.")

                        HStack {
                            Text("Milestones")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                draft.milestones.append(MilestoneDraft())
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                            }
                            .tint(auth.accentColor)
                        }

                        ForEach($draft.milestones) { $m in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Milestone")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(role: .destructive) {
                                        if let idx = draft.milestones.firstIndex(where: { $0.id == m.id }) {
                                            draft.milestones.remove(at: idx)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                field("Title", text: $m.title, placeholder: "Title")
                                field("Description", text: $m.description, placeholder: "Description")
                                DatePicker(
                                    "Expected date (optional)",
                                    selection: Binding(
                                        get: { m.expectedDate ?? Date() },
                                        set: { m.expectedDate = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                            }
                            .padding(12)
                            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                                    .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
                            )
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(AppTheme.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "Saving…" : "Save changes")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(auth.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                    .disabled(!canSave || isSaving)
                    .opacity(canSave && !isSaving ? 1 : 0.45)
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 8)
                .padding(.bottom, 24)
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

    private func formSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private var canSave: Bool {
        let t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = draft.useOfFunds.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !c.isEmpty, !d.isEmpty, !loc.isEmpty, !u.isEmpty else { return false }
        let cleaned = draft.amount.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let amt = Double(cleaned), amt > 0 else { return false }
        return (try? OpportunityService.validateDraftTerms(draft)) != nil
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
        d.investmentType = listing.investmentType
        d.title = listing.title
        d.category = listing.category
        d.description = listing.description
        d.location = listing.location
        d.amount = String(format: "%.0f", listing.amountRequested)
        d.minimumInvestment = listing.minimumInvestment > 0 ? String(format: "%.0f", listing.minimumInvestment) : ""
        if let max = listing.maximumInvestors {
            d.maximumInvestors = String(max)
        }
        d.riskLevel = listing.riskLevel
        d.verificationStatus = listing.verificationStatus
        d.useOfFunds = listing.useOfFunds
        d.milestones = listing.milestones.map { m in
            MilestoneDraft(title: m.title, description: m.description, expectedDate: m.expectedDate)
        }

        let t = listing.terms
        switch listing.investmentType {
        case .loan:
            if let r = t.interestRate {
                d.interestRate = r == floor(r) ? String(Int(r)) : String(r)
            }
            if let m = t.repaymentTimelineMonths {
                d.repaymentTimeline = "\(m)"
            }
            if let f = t.repaymentFrequency {
                d.repaymentFrequency = f
            }
        case .equity:
            if let p = t.equityPercentage {
                d.equityPercentage = p == floor(p) ? String(Int(p)) : String(p)
            }
            if let v = t.businessValuation {
                d.businessValuation = String(format: "%.0f", v)
            }
            d.exitPlan = t.exitPlan ?? ""
        case .revenue_share:
            if let p = t.revenueSharePercent {
                d.revenueSharePercent = String(p)
            }
            if let tr = t.targetReturnAmount {
                d.targetReturnAmount = String(format: "%.0f", tr)
            }
            if let mx = t.maxDurationMonths {
                d.maxDurationMonths = String(mx)
            }
        case .project:
            if let rt = t.expectedReturnType {
                d.expectedReturnType = rt
            }
            d.expectedReturnValue = t.expectedReturnValue ?? ""
            d.completionDate = t.completionDate
        case .custom:
            d.customTermsSummary = t.customTermsSummary ?? ""
        }
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
                .background(AuthTheme.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                        .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1)
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
            .background(AuthTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1)
            )
        }
    }
}
