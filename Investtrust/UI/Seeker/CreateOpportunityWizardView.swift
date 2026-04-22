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

    private let steps = ["Type", "Overview", "Funding", "Terms", "Execution", "Review"]

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

            VStack(spacing: 0) {
                ForEach(InvestmentType.allCases, id: \.self) { type in
                    Button {
                        draft.investmentType = type
                    } label: {
                        HStack {
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
                    }
                    .buttonStyle(.plain)
                    if type != InvestmentType.allCases.last {
                        Divider()
                    }
                }
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1)
            )
            .appCardShadow()
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

    private var overviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Overview", "Title, category, and story — plus optional images and video.")
            stepFormCard {
                VStack(alignment: .leading, spacing: 16) {
                    field("Opportunity title", text: $draft.title, placeholder: "Ex: Mobile juice cart expansion")
                    field("Category", text: $draft.category, placeholder: "Food / Retail / Freelance")
                    textArea("Description", text: $draft.description, placeholder: "What you’re building and why investors should care.")
                }
            }
            mediaPickerCard
        }
    }

    private var fundingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Funding & risk", "How much you need, ticket size, and where you operate.")
            stepFormCard {
                VStack(alignment: .leading, spacing: 16) {
                    field("Amount needed (LKR)", text: $draft.amount, placeholder: "150000", keyboardType: .numberPad)
                    field("Minimum investment (LKR)", text: $draft.minimumInvestment, placeholder: "Leave blank to auto (1% of goal, capped)")
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

                    Text("Verification is set by the platform after review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        }
    }

    private var executionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Execution plan", "What the money buys, milestones, and timing.")
            stepFormCard {
                VStack(alignment: .leading, spacing: 16) {
                    textArea("Use of funds", text: $draft.useOfFunds, placeholder: "Exactly what you’ll spend on — inventory, marketing, equipment, etc.")

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Milestones")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                draft.milestones.append(MilestoneDraft())
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
                                            .font(.body)
                                    }
                                }
                                field("Title", text: $m.title, placeholder: "e.g. First production batch")
                                field("Description", text: $m.description, placeholder: "What’s delivered and how success is measured")
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
                }
            }
        }
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
                    ("Images", selectedImageDataList.isEmpty ? "0" : "\(selectedImageDataList.count)"),
                    ("Video", selectedVideoData == nil ? "No" : "Yes")
                ]
            )
            reviewCard(
                title: "Funding",
                rows: [
                    ("Amount", "LKR \(draft.amount)"),
                    ("Minimum", draft.minimumInvestment.isEmpty ? "(auto)" : "LKR \(draft.minimumInvestment)"),
                    ("Max investors", draft.maximumInvestors.isEmpty ? "—" : draft.maximumInvestors),
                    ("Risk", draft.riskLevel.displayName),
                    ("Location", draft.location)
                ]
            )
            reviewCard(title: "Terms", rows: termsReviewRows)
            reviewCard(
                title: "Execution",
                rows: [
                    ("Use of funds", draft.useOfFunds),
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
            rows.append(("Timeline", draft.repaymentTimeline.isEmpty ? "—" : "\(draft.repaymentTimeline) mo"))
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
            return !t.isEmpty && !c.isEmpty && !d.isEmpty
        case 2:
            guard parsePositiveAmount(draft.amount) != nil else { return false }
            let loc = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !loc.isEmpty else { return false }
            if let minStr = optionalDoubleString(draft.minimumInvestment), let goal = parsePositiveAmount(draft.amount) {
                if minStr > goal { return false }
            }
            return true
        case 3:
            return (try? OpportunityService.validateDraftTerms(draft)) != nil
        case 4:
            return !draft.useOfFunds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private func parsePositiveAmount(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let v = Double(cleaned), v > 0 else { return nil }
        return v
    }

    private func optionalDoubleString(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return parsePositiveAmount(t)
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

            HStack(spacing: 10) {
                PhotosPicker(selection: $imagePickerItems, maxSelectionCount: 5, matching: .images) {
                    Label(selectedImageDataList.isEmpty ? "Upload images (max 5)" : "Change images (\(selectedImageDataList.count)/5)", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }

                PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                    Label(selectedVideoData == nil ? "Upload video (max 1)" : "Change video", systemImage: "video")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.secondaryFill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }
            }

            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            if let selectedVideoData {
                Label("Video attached (\(ByteCountFormatter.string(fromByteCount: Int64(selectedVideoData.count), countStyle: .file)))", systemImage: "video.fill")
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
