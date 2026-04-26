//
//  CreateOpportunityWizardView.swift
//  Investtrust
//

import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Loads a picked video file via `Transferable` / `FileRepresentation` (no `PhotosPickerItem.itemProvider`, which isn’t available on all SDKs).
private struct PickedVideoData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie, shouldAttemptToOpenInPlace: true) { received in
            let url = received.file
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw NSError(
                    domain: "Investtrust",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Video file was empty."]
                )
            }
            return PickedVideoData(data: data)
        }
    }
}

struct CreateOpportunityWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @State private var draft = OpportunityDraft()
    @State private var allowsMultipleInvestors = true
    @State private var currentStep = 0
    @State private var showSavedAlert = false
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var imageScreeningMessage: String?
    @State private var imagePickerItems: [PhotosPickerItem] = []
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var selectedImageDataList: [Data] = []
    @State private var selectedVideoData: Data?
    @State private var videoPickerError: String?
    @State private var selectedImages: [Image] = []
    @State private var didPrefillLocation = false

    private let steps = ["Type", "Overview", "Funding", "Terms", "Execution", "Review"]
    private let userService = UserService()

    var onSubmit: (OpportunityDraft, [Data], Data?) async throws -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        progressHeader

                        Group {
                            switch currentStep {
                            case 0: investmentTypeStep
                            case 1: overviewStep
                            case 2: fundingStep
                            case 3: termsStep
                            case 4: executionStep
                            default: reviewStep
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .padding(AppTheme.screenPadding)
                }

                footerButtons
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Create opportunity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Opportunity ready", isPresented: $showSavedAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your opportunity draft has been added to the Create tab.")
            }
            .alert("Couldn't submit", isPresented: .constant(submitError != nil)) {
                Button("OK") { submitError = nil }
            } message: {
                Text(submitError ?? "")
            }
            .alert("Image screening", isPresented: Binding(
                get: { imageScreeningMessage != nil },
                set: { if !$0 { imageScreeningMessage = nil } }
            )) {
                Button("OK") { imageScreeningMessage = nil }
            } message: {
                Text(imageScreeningMessage ?? "")
            }
            .onChange(of: imagePickerItems) { _, newValues in
                Task {
                    var loadedData: [Data] = []
                    var loadedImages: [Image] = []
                    for item in newValues.prefix(5) {
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let uiImage = UIImage(data: data) else { continue }
                        do {
                            try await InappropriateImageGate.validateForUpload(uiImage)
                            let jpeg = uiImage.jpegData(compressionQuality: 0.88) ?? data
                            loadedData.append(jpeg)
                            loadedImages.append(Image(uiImage: uiImage))
                        } catch {
                            await MainActor.run {
                                imageScreeningMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                imagePickerItems = []
                                selectedImageDataList = []
                                selectedImages = []
                            }
                            return
                        }
                    }
                    await MainActor.run {
                        selectedImageDataList = loadedData
                        selectedImages = loadedImages
                    }
                }
            }
            .onChange(of: videoPickerItem) { _, newValue in
                guard let newValue else {
                    selectedVideoData = nil
                    videoPickerError = nil
                    return
                }
                Task {
                    do {
                        let data = try await loadVideoData(from: newValue)
                        selectedVideoData = data
                        videoPickerError = nil
                    } catch {
                        selectedVideoData = nil
                        videoPickerError = error.localizedDescription
                    }
                }
            }
            .task {
                await prefillLocationFromProfileIfNeeded()
                syncFundingModeFromDraft()
            }
            .onChange(of: allowsMultipleInvestors) { _, allowsMultiple in
                applyFundingMode(allowsMultiple)
            }
            .onChange(of: currentStep) { _, newStep in
                if newStep == 4 {
                    seedDefaultMilestonesIfNeeded()
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step \(currentStep + 1) of \(steps.count): \(steps[currentStep])")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.secondaryFill)
                        .frame(height: 8)

                    Capsule()
                        .fill(auth.accentColor)
                        .frame(width: max(14, geo.size.width * progress), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private var investmentTypeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What type of investment are you creating?")
                .font(.headline)
            Text("We’ll only ask for fields that match this type — clearer for you and for investors.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(InvestmentType.allCases, id: \.self) { type in
                    Button {
                        draft.investmentType = type
                    } label: {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(typeIconTint(type).opacity(0.14))
                                    .frame(width: 38, height: 38)
                                Image(systemName: typeIcon(type))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(typeIconTint(type))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(typeBlurb(type))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if draft.investmentType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(auth.accentColor)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                                .fill(draft.investmentType == type ? auth.accentColor.opacity(0.08) : AppTheme.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                                .strokeBorder(
                                    draft.investmentType == type ? auth.accentColor.opacity(0.55) : AuthTheme.fieldBorder,
                                    lineWidth: draft.investmentType == type ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func typeBlurb(_ type: InvestmentType) -> String {
        switch type {
        case .loan:
            return "Fixed repayments with interest and schedule."
        case .equity:
            return "Ownership stake, valuation, exit plan."
        case .revenue_share:
            return "Share of revenue until a target return."
        case .project:
            return "Deliverable-based with expected return and completion."
        case .custom:
            return "Describe bespoke terms in your own words."
        }
    }

    private func typeIcon(_ type: InvestmentType) -> String {
        switch type {
        case .loan:
            return "banknote.fill"
        case .equity:
            return "chart.pie.fill"
        case .revenue_share:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .project:
            return "hammer.fill"
        case .custom:
            return "slider.horizontal.3"
        }
    }

    private func typeIconTint(_ type: InvestmentType) -> Color {
        switch type {
        case .loan:
            return .green
        case .equity:
            return .blue
        case .revenue_share:
            return .orange
        case .project:
            return .purple
        case .custom:
            return auth.accentColor
        }
    }

    private var overviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Overview", "Title, category, and story — plus optional images and video.")
            stepFormCard {
                VStack(alignment: .leading, spacing: 16) {
                    field("Opportunity title", text: $draft.title, placeholder: "Ex: Mobile juice cart expansion")
                    field("Category", text: $draft.category, placeholder: "Food / Retail / Freelance")
                    textArea("Description", text: $draft.description, placeholder: "What you’re building and why investors should care.")
                    textArea(
                        "Income generation method",
                        text: $draft.incomeGenerationMethod,
                        placeholder: "Explain in detail how revenue or cash flows will be generated to repay or reward investors."
                    )
                }
            }
            mediaPickerCard
        }
    }

    private var fundingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Funding setup", "Set amount and choose whether one investor or multiple investors can join.")
            stepFormCard {
                VStack(alignment: .leading, spacing: 16) {
                    field("Amount needed (LKR)", text: $draft.amount, placeholder: "150000", keyboardType: .numberPad)
                    textArea("Use of funds", text: $draft.useOfFunds, placeholder: "What exactly will this funding be used for?")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Investor setup")
                            .font(.subheadline.weight(.semibold))
                        Picker("Investor setup", selection: $allowsMultipleInvestors) {
                            Text("Single investor").tag(false)
                            Text("Multiple investors").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                    if allowsMultipleInvestors {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Negotiation")
                                .font(.subheadline.weight(.semibold))
                            Text("Negotiation is unavailable for multiple investors.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Toggle(isOn: $draft.isNegotiable) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow negotiation")
                                    .font(.subheadline.weight(.semibold))
                                Text("If enabled, investors will see the Make offer button.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(auth.accentColor)
                    }

                    if allowsMultipleInvestors {
                        field("Maximum investors", text: $draft.maximumInvestors, placeholder: "e.g. 10")
                        Text("Each investor’s ticket is the goal divided by this cap (equal shares).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Single investor mode")
                                .font(.subheadline.weight(.semibold))
                            Text("This listing will be filled by one investor. Minimum investment is automatically the full funding goal.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    }
                }
            }
        }
    }

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Investment terms", "Details for \(draft.investmentType.displayName.lowercased()).")
            stepFormCard {
                Group {
                    switch draft.investmentType {
                case .loan:
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
                    field("Interest rate (%)", text: $draft.interestRate, placeholder: "12", keyboardType: .decimalPad)
                    field(loanTimelineFieldTitle, text: $draft.repaymentTimeline, placeholder: loanTimelinePlaceholder)
                    Text(loanTimelineHelperText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .equity:
                    field("Equity offered (%)", text: $draft.equityPercentage, placeholder: "10", keyboardType: .decimalPad)
                    field("Business valuation (LKR, optional)", text: $draft.businessValuation, placeholder: "5000000", keyboardType: .numberPad)
                    textArea("Exit plan", text: $draft.exitPlan, placeholder: "How and when investors may realize returns.")
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
                    field("Expected return (describe)", text: $draft.expectedReturnValue, placeholder: "e.g. 15% on completion / product units")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target completion date")
                            .font(.subheadline.weight(.semibold))
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { draft.completionDate ?? Date() },
                                set: { draft.completionDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                case .custom:
                    textArea("Custom terms summary", text: $draft.customTermsSummary, placeholder: "Spell out the deal in plain language.")
                }
                }
            }
            Text("Tip: specific terms build trust on the marketplace.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            seekerCommitmentsPreview
        }
    }

    private var executionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Milestones", "Plan your progress updates. We prefilled suggested milestones you can edit.")
            stepFormCard {
                VStack(alignment: .leading, spacing: 16) {
                    let spanDays = inferredTenorDaysApproximate()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(auth.accentColor)
                            Text("Deal span from acceptance")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text("About \(spanDays) days")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Milestones use days after your investment is accepted — not today’s date. Suggested defaults scale to this rough span.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [auth.accentColor.opacity(0.14), AppTheme.secondaryFill],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            .strokeBorder(auth.accentColor.opacity(0.25), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Milestones")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                draft.milestones.insert(MilestoneDraft(), at: 0)
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .tint(auth.accentColor)
                        }

                        if draft.milestones.isEmpty {
                            Text("Add milestones so investors see when to expect progress.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ForEach($draft.milestones) { $m in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    HStack(spacing: 8) {
                                        milestoneNumberBadge(for: m)
                                        Text(m.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled milestone" : m.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        if let idx = draft.milestones.firstIndex(where: { $0.id == m.id }) {
                                            draft.milestones.remove(at: idx)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.body)
                                    }
                                }
                                field("Title", text: $m.title, placeholder: "e.g. First production batch")
                                field("Description", text: $m.description, placeholder: "What’s delivered and how success is measured")
                                field(
                                    "Due within (days after investment is accepted)",
                                    text: $m.daysAfterAcceptance,
                                    placeholder: "e.g. 30",
                                    keyboardType: .numberPad
                                )
                                Text("Day 0 is when the seeker accepts your investment on the platform.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(
                                milestoneCardBackground(for: m),
                                in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                                    .strokeBorder(milestoneCardBorder(for: m), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private func milestoneNumberBadge(for milestone: MilestoneDraft) -> some View {
        let idx = (draft.milestones.firstIndex(where: { $0.id == milestone.id }) ?? 0) + 1
        return Text("\(idx)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(auth.accentColor, in: Circle())
    }

    private func milestoneCardBackground(for milestone: MilestoneDraft) -> Color {
        let idx = draft.milestones.firstIndex(where: { $0.id == milestone.id }) ?? 0
        return idx.isMultiple(of: 2) ? AppTheme.cardBackground : AppTheme.secondaryFill.opacity(0.65)
    }

    private func milestoneCardBorder(for milestone: MilestoneDraft) -> Color {
        let digits = milestone.daysAfterAcceptance.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        if !digits.isEmpty, Int(digits) != nil {
            return auth.accentColor.opacity(0.28)
        }
        return Color(uiColor: .separator).opacity(0.35)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review your listing")
                .font(.title3.bold())

            reviewCard(
                title: "Type",
                rows: [
                    ("Investment type", draft.investmentType.displayName)
                ]
            )
            reviewCard(
                title: "Overview",
                rows: [
                    ("Title", draft.title),
                    ("Category", draft.category),
                    ("Description", draft.description),
                    ("Income generation", draft.incomeGenerationMethod.isEmpty ? "—" : String(draft.incomeGenerationMethod.prefix(120)) + (draft.incomeGenerationMethod.count > 120 ? "…" : "")),
                    ("Images", selectedImageDataList.isEmpty ? "0" : "\(selectedImageDataList.count)"),
                    ("Video", selectedVideoData == nil ? "No" : "Yes")
                ]
            )
            reviewCard(
                title: "Funding",
                rows: [
                    ("Amount", "LKR \(draft.amount)"),
                    ("Investor setup", allowsMultipleInvestors ? "Multiple investors" : "Single investor"),
                    ("Per-investor ticket", reviewPerInvestorTicketSummary()),
                    ("Max investors", allowsMultipleInvestors ? (draft.maximumInvestors.isEmpty ? "—" : draft.maximumInvestors) : "1"),
                    ("Negotiable", draft.isNegotiable ? "Yes" : "No"),
                    ("Use of funds", draft.useOfFunds)
                ]
            )
            reviewCard(title: "Terms", rows: termsReviewRows)
            if !seekerCommitmentReviewRows.isEmpty {
                reviewCard(title: "What you’re committing to", rows: seekerCommitmentReviewRows)
            }
            reviewCard(
                title: "Execution",
                rows: [
                    ("Milestones", "\(draft.milestones.count) added")
                ]
            )
        }
    }

    private var termsReviewRows: [(String, String)] {
        var rows: [(String, String)] = [("Structure", draft.investmentType.displayName)]
        switch draft.investmentType {
        case .loan:
            rows.append(("Interest", draft.interestRate.isEmpty ? "—" : "\(draft.interestRate)%"))
            rows.append(("Timeline", reviewLoanTimelineText))
            rows.append(("Frequency", draft.repaymentFrequency.rawValue.capitalized))
        case .equity:
            rows.append(("Equity %", draft.equityPercentage))
            rows.append(("Valuation", draft.businessValuation.isEmpty ? "—" : "LKR \(draft.businessValuation)"))
            rows.append(("Exit", draft.exitPlan.isEmpty ? "—" : String(draft.exitPlan.prefix(120))))
        case .revenue_share:
            rows.append(("Rev. share", draft.revenueSharePercent))
            rows.append(("Target", draft.targetReturnAmount.isEmpty ? "—" : "LKR \(draft.targetReturnAmount)"))
            rows.append(("Max months", draft.maxDurationMonths))
        case .project:
            rows.append(("Return type", draft.expectedReturnType.rawValue.capitalized))
            rows.append(("Expected return", draft.expectedReturnValue))
            if let d = draft.completionDate {
                let f = DateFormatter()
                f.dateStyle = .medium
                rows.append(("Completion", f.string(from: d)))
            }
        case .custom:
            rows.append(("Summary", draft.customTermsSummary.isEmpty ? "—" : String(draft.customTermsSummary.prefix(160))))
        }
        return rows
    }

    private func reviewPerInvestorTicketSummary() -> String {
        guard let goal = parsePositiveAmount(draft.amount) else { return "—" }
        if allowsMultipleInvestors {
            guard let cap = parseInvestorCap(draft.maximumInvestors), cap >= 2 else { return "—" }
            let raw = goal / Double(cap)
            let share = (raw * 100).rounded() / 100
            return "LKR \(reviewFundingNumberString(share))"
        }
        return "LKR \(reviewFundingNumberString(goal))"
    }

    private func reviewFundingNumberString(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.000_001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private var seekerCommitmentsPreview: some View {
        let rows = seekerCommitmentReviewRows
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(auth.accentColor)
                    .frame(width: 36, height: 36)
                    .background(auth.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your commitments (preview)")
                        .font(.headline)
                    Text("Modeled payback if the round fills and installments start today—same simple-interest rules investors see on your listing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if rows.isEmpty {
                Text(seekerCommitmentMissingHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text("• \(row.0): \(row.1)")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [auth.accentColor.opacity(0.1), AppTheme.secondaryFill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(auth.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var seekerCommitmentMissingHint: String {
        switch draft.investmentType {
        case .loan:
            return "Add your funding goal, interest rate, and repayment timeline to preview total payback and payment dates."
        case .equity:
            return "Add your funding goal and equity percentage to preview what you’re offering."
        case .revenue_share:
            return "Add revenue share %, target payout, and max duration to preview the investor cap you’re accepting."
        case .project:
            return "Describe the expected return and set a completion date so backers know what you’re promising."
        case .custom:
            return "Write your custom terms summary—buyers will rely on it, and we surface it on the listing."
        }
    }

    private var seekerCommitmentReviewRows: [(String, String)] {
        switch draft.investmentType {
        case .loan:
            guard let goal = parsePositiveAmount(draft.amount),
                  let rate = parseNonNegativeDouble(draft.interestRate),
                  let rawTimeline = loanTimelineDigitsFromDraft(),
                  rawTimeline > 0 else { return [] }
            let months = OpportunityFinancialPreview.loanTermMonthsFromWizardInput(
                rawTimeline: rawTimeline,
                repaymentFrequency: draft.repaymentFrequency
            )
            let plan = LoanRepaymentPlan.from(draft.repaymentFrequency)
            guard let preview = OpportunityFinancialPreview.loanMoneyOutcome(
                principal: goal,
                annualRatePercent: rate,
                termMonths: months,
                plan: plan
            ) else { return [] }
            var rows: [(String, String)] = [
                ("Modeled total repayable (full goal)", "LKR \(OpportunityFinancialPreview.formatLKRInteger(preview.totalRepayable))"),
                ("Interest (simple)", "LKR \(OpportunityFinancialPreview.formatLKRInteger(preview.interestAmount))"),
                ("Rate / term basis", "\(formatWizardRate(rate))% · \(months) months")
            ]
            if let first = preview.firstInstallmentDue, let last = preview.maturityDue {
                if first == last {
                    rows.append(("Modeled payment date", OpportunityFinancialPreview.mediumDate(first)))
                } else {
                    rows.append(("First modeled installment", OpportunityFinancialPreview.mediumDate(first)))
                    rows.append(("Final modeled payment", OpportunityFinancialPreview.mediumDate(last)))
                }
            }
            return rows
        case .equity:
            guard let goal = parsePositiveAmount(draft.amount),
                  let eq = parseNonNegativeDouble(draft.equityPercentage), eq > 0 else { return [] }
            var rows: [(String, String)] = [
                ("Equity offered if round fills", "\(formatWizardRate(eq))% for LKR \(OpportunityFinancialPreview.formatLKRInteger(goal)) raised")
            ]
            if let v = parsePositiveAmount(draft.businessValuation) {
                rows.append(("Stated valuation", "LKR \(OpportunityFinancialPreview.formatLKRInteger(v))"))
            }
            return rows
        case .revenue_share:
            guard let p = parseNonNegativeDouble(draft.revenueSharePercent), p > 0,
                  let target = parsePositiveAmount(draft.targetReturnAmount) else { return [] }
            let digits = draft.maxDurationMonths.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
            var rows: [(String, String)] = [
                ("Revenue share", "\(formatWizardRate(p))% of revenue"),
                ("Investor return cap", "LKR \(OpportunityFinancialPreview.formatLKRInteger(target))")
            ]
            if let m = Int(digits), m > 0 {
                rows.append(("Duration cap", "\(m) months"))
            }
            return rows
        case .project:
            let val = draft.expectedReturnValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !val.isEmpty else { return [] }
            var rows: [(String, String)] = [("Expected return", val)]
            if let d = draft.completionDate {
                rows.append(("Target completion", shortDate(d)))
            }
            return rows
        case .custom:
            let s = draft.customTermsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return [] }
            let clip = s.count > 200 ? String(s.prefix(200)) + "…" : s
            return [("Custom obligations (summary)", clip)]
        }
    }

    private func loanTimelineDigitsFromDraft() -> Int? {
        let digits = draft.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        return Int(digits)
    }

    private func parseNonNegativeDouble(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let v = Double(cleaned), v >= 0 else { return nil }
        return v
    }

    private func formatWizardRate(_ v: Double) -> String {
        if abs(v - floor(v)) < 0.000_001 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func stepFormCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .appCardShadow()
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button("Back") {
                    currentStep -= 1
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(currentStep == steps.count - 1 ? (isSubmitting ? "Submitting..." : "Submit") : "Next") {
                if currentStep == steps.count - 1 {
                    Task {
                        isSubmitting = true
                        defer { isSubmitting = false }
                        do {
                            normalizeFundingDraftBeforeSubmit()
                            normalizeLoanTermsBeforeSubmit()
                            try await onSubmit(draft, selectedImageDataList, selectedVideoData)
                            showSavedAlert = true
                        } catch {
                            submitError = readableErrorMessage(for: error)
                        }
                    }
                } else {
                    currentStep += 1
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(auth.accentColor, in: Capsule())
            .foregroundStyle(.white)
            .disabled(!canContinue || isSubmitting)
            .opacity((canContinue && !isSubmitting) ? 1 : 0.45)
        }
    }

    private var progress: CGFloat {
        CGFloat(currentStep + 1) / CGFloat(steps.count)
    }

    private var canContinue: Bool {
        switch currentStep {
        case 0:
            return true
        case 1:
            let t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let c = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let income = draft.incomeGenerationMethod.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !c.isEmpty && !d.isEmpty && !income.isEmpty
        case 2:
            guard parsePositiveAmount(draft.amount) != nil else { return false }
            guard !draft.useOfFunds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if allowsMultipleInvestors {
                guard let cap = parseInvestorCap(draft.maximumInvestors), cap >= 2 else { return false }
            }
            return true
        case 3:
            return (try? OpportunityService.validateDraftTerms(normalizedDraftForTermsValidation())) != nil
        case 4:
            return validateMilestoneDraftOffsets()
        default:
            return true
        }
    }

    private func parsePositiveAmount(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let v = Double(cleaned), v > 0 else { return nil }
        return v
    }

    private func parseInvestorCap(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let digits = t.filter(\.isNumber)
        return Int(digits)
    }

    private func normalizeFundingDraftBeforeSubmit() {
        if allowsMultipleInvestors {
            draft.isNegotiable = false
            if let cap = parseInvestorCap(draft.maximumInvestors), cap >= 2 {
                draft.maximumInvestors = "\(cap)"
            } else {
                draft.maximumInvestors = ""
            }
            return
        }
        draft.maximumInvestors = "1"
    }

    private func normalizeLoanTermsBeforeSubmit() {
        guard draft.investmentType == .loan else { return }
        guard draft.repaymentFrequency == .weekly else { return }
        let digits = draft.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        guard let weeks = Int(digits), weeks > 0 else { return }
        let months = max(1, Int((Double(weeks) / LoanScheduleGenerator.weeksPerMonth).rounded()))
        draft.repaymentTimeline = "\(months)"
    }

    private func normalizedDraftForTermsValidation() -> OpportunityDraft {
        guard draft.investmentType == .loan, draft.repaymentFrequency == .weekly else {
            return draft
        }
        var copy = draft
        let digits = copy.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        if let weeks = Int(digits), weeks > 0 {
            let months = max(1, Int((Double(weeks) / LoanScheduleGenerator.weeksPerMonth).rounded()))
            copy.repaymentTimeline = "\(months)"
        }
        return copy
    }

    private func applyFundingMode(_ allowsMultiple: Bool) {
        if allowsMultiple {
            draft.isNegotiable = false
            if draft.maximumInvestors.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                draft.maximumInvestors = ""
            }
            return
        }
        draft.maximumInvestors = "1"
    }

    private func syncFundingModeFromDraft() {
        let cap = parseInvestorCap(draft.maximumInvestors) ?? 0
        allowsMultipleInvestors = cap != 1
    }

    private func prefillLocationFromProfileIfNeeded() async {
        if didPrefillLocation { return }
        didPrefillLocation = true
        guard draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let uid = auth.currentUserID else { return }
        guard let profile = try? await userService.fetchProfile(userID: uid) else { return }
        let city = profile.profileDetails?.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = profile.profileDetails?.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location: String
        if !city.isEmpty, !country.isEmpty {
            location = "\(city), \(country)"
        } else if !city.isEmpty {
            location = city
        } else if !country.isEmpty {
            location = country
        } else {
            location = ""
        }
        if !location.isEmpty {
            await MainActor.run {
                draft.location = location
            }
        }
    }

    private func seedDefaultMilestonesIfNeeded() {
        if !draft.milestones.isEmpty { return }
        let span = inferredTenorDaysApproximate()
        let half = max(1, span / 2)
        let tail = max(1, span / 10)
        let nearEnd = min(span, max(half + 1, span - tail))
        draft.milestones = [
            MilestoneDraft(
                title: "Midway progress update",
                description: "Share progress around the halfway point of the deal window—what’s done and what’s next.",
                daysAfterAcceptance: "\(half)"
            ),
            MilestoneDraft(
                title: "Near completion update",
                description: "A final checkpoint before the end of the window: delivery status, outcomes, and any wrap-up.",
                daysAfterAcceptance: "\(nearEnd)"
            )
        ]
    }

    /// Rough span in days from investment acceptance (for milestone defaults and hints).
    private func inferredTenorDaysApproximate() -> Int {
        let calendar = Calendar.current
        switch draft.investmentType {
        case .loan:
            let digits = draft.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
            guard let timeline = Int(digits), timeline > 0 else { return 180 }
            let months: Int
            switch draft.repaymentFrequency {
            case .weekly:
                months = max(1, Int((Double(timeline) / LoanScheduleGenerator.weeksPerMonth).rounded()))
            case .monthly, .one_time:
                months = timeline
            }
            return min(3650, max(30, months * 30))
        case .revenue_share:
            let m = Int(draft.maxDurationMonths.filter(\.isNumber)) ?? 12
            return min(3650, max(30, m * 30))
        case .project:
            if let end = draft.completionDate {
                let days = calendar.dateComponents([.day], from: Date(), to: end).day ?? 180
                return min(3650, max(30, days))
            }
            return 180
        case .equity, .custom:
            return 180
        }
    }

    /// Each milestone with any content must have a valid “days after acceptance” (list order is free-form; new rows are added on top).
    private func validateMilestoneDraftOffsets() -> Bool {
        for m in draft.milestones {
            let hasContent =
                !m.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !m.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !m.daysAfterAcceptance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasContent { continue }
            let digits = m.daysAfterAcceptance.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
            guard let n = Int(digits), n >= 0, n <= 3650 else { return false }
        }
        return true
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private var loanTimelineFieldTitle: String {
        switch draft.repaymentFrequency {
        case .weekly:
            return "Repayment timeline (weeks)"
        case .monthly:
            return "Repayment timeline (months)"
        case .one_time:
            return "Maturity timeline (months)"
        }
    }

    private var loanTimelinePlaceholder: String {
        switch draft.repaymentFrequency {
        case .weekly:
            return "24"
        case .monthly:
            return "12"
        case .one_time:
            return "6"
        }
    }

    private var loanTimelineHelperText: String {
        switch draft.repaymentFrequency {
        case .weekly:
            return "Enter the number of weeks. We convert this to the equivalent loan term for scheduling."
        case .monthly:
            return "Enter total repayment duration in months."
        case .one_time:
            return "Enter months until one-time repayment at maturity."
        }
    }

    private var reviewLoanTimelineText: String {
        let value = draft.repaymentTimeline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "—" }
        switch draft.repaymentFrequency {
        case .weekly:
            return "\(value) weeks"
        case .monthly:
            return "\(value) months"
        case .one_time:
            return "\(value) months (maturity)"
        }
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

    private func textArea(
        _ label: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
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

    private var mediaPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Media")
                .font(.subheadline.weight(.semibold))
            Text("Add up to 5 photos and one video. Good media helps investors evaluate faster.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                PhotosPicker(selection: $imagePickerItems, maxSelectionCount: 5, matching: .images) {
                    mediaPickerRow(
                        title: "Photos",
                        subtitle: selectedImageDataList.isEmpty
                            ? "Upload up to 5 images"
                            : "\(selectedImageDataList.count) selected"
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 14)

                PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                    mediaPickerRow(
                        title: "Video",
                        subtitle: selectedVideoData == nil
                            ? "Upload one video (optional)"
                            : "Video attached"
                    )
                }
                .buttonStyle(.plain)
            }
            .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
            )

            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(6)
                                }
                        }
                    }
                }
            }

            if let selectedVideoData {
                Text("Video attached · \(ByteCountFormatter.string(fromByteCount: Int64(selectedVideoData.count), countStyle: .file))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let videoPickerError {
                Text(videoPickerError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1)
        )
    }

    private func mediaPickerRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Choose")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func reviewCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(auth.accentColor)
                Text(title)
                    .font(.headline)
            }
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top) {
                    Text(rows[index].0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rows[index].1.isEmpty ? "—" : rows[index].1)
                        .font(.subheadline)
                        .multilineTextAlignment(.trailing)
                }
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    /// Tries raw `Data` first, then `FileRepresentation` via `PickedVideoData` (handles large / file-backed clips).
    private func loadVideoData(from item: PhotosPickerItem) async throws -> Data {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            return data
        }
        if let picked = try? await item.loadTransferable(type: PickedVideoData.self) {
            return picked.data
        }
        throw NSError(
            domain: "Investtrust",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Could not read the video file. Try a shorter clip or a different format."]
        )
    }

    private func readableErrorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        let nsError = error as NSError

        let message = nsError.localizedDescription.lowercased()
        if message.contains("permission") || message.contains("unauthorized") {
            return "Permission denied from Firebase. Check Firestore/Storage rules for authenticated users."
        }
        if message.contains("timed out") {
            return "Request timed out. Check your network and Firebase Storage setup, then try again."
        }
        return nsError.localizedDescription
    }
}

#Preview {
    CreateOpportunityWizardView { _, _, _ in }
        .environment(AuthService.previewSignedIn)
}
