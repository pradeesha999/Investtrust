//
//  CreateOpportunityWizardView.swift
//  Investtrust
//

import PhotosUI
import SwiftUI
import UIKit

struct CreateOpportunityWizardView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft = OpportunityDraft()
    @State private var currentStep = 0
    @State private var showSavedAlert = false
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var imagePickerItems: [PhotosPickerItem] = []
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var selectedImageDataList: [Data] = []
    @State private var selectedVideoData: Data?
    @State private var selectedImages: [Image] = []

    private let steps = ["Basics", "Terms", "Details", "Review"]

    var onSubmit: (OpportunityDraft, [Data], Data?) async throws -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                progressHeader

                Group {
                    switch currentStep {
                    case 0: basicStep
                    case 1: termsStep
                    case 2: detailsStep
                    default: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footerButtons
            }
            .padding(20)
            .background(Color.white)
            .navigationTitle("Create Investment")
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
                Text("Your opportunity draft has been added to the dashboard.")
            }
            .alert("Couldn't submit", isPresented: .constant(submitError != nil)) {
                Button("OK") { submitError = nil }
            } message: {
                Text(submitError ?? "")
            }
            .onChange(of: imagePickerItems) { _, newValues in
                Task {
                    var loadedData: [Data] = []
                    var loadedImages: [Image] = []
                    for item in newValues.prefix(5) {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            let jpeg = uiImage.jpegData(compressionQuality: 0.88) ?? data
                            loadedData.append(jpeg)
                            loadedImages.append(Image(uiImage: uiImage))
                        }
                    }
                    selectedImageDataList = loadedData
                    selectedImages = loadedImages
                }
            }
            .onChange(of: videoPickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        selectedVideoData = data
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
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 8)

                    Capsule()
                        .fill(AuthTheme.primaryPink)
                        .frame(width: max(14, geo.size.width * progress), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private var basicStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Opportunity title", text: $draft.title, placeholder: "Ex: Mobile juice cart expansion")
            field("Category", text: $draft.category, placeholder: "Food / Retail / Freelance")
            field("Amount needed (LKR)", text: $draft.amount, placeholder: "150000", keyboardType: .numberPad)
        }
    }

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Interest rate (%)", text: $draft.interestRate, placeholder: "12", keyboardType: .decimalPad)
            field("Repayment timeline", text: $draft.repaymentTimeline, placeholder: "12 months")

            Text("Tip: keep terms realistic so investors trust the listing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            textArea("Description", text: $draft.description, placeholder: "Explain how this investment will be used.")
            mediaPickerCard
        }
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Review your listing")
                    .font(.title3.bold())

                Group {
                    reviewCard(
                        title: "Basics",
                        rows: [
                            ("Title", draft.title),
                            ("Category", draft.category),
                            ("Amount", "LKR \(draft.amount)")
                        ]
                    )
                    reviewCard(
                        title: "Terms",
                        rows: [
                            ("Interest", "\(draft.interestRate)%"),
                            ("Timeline", draft.repaymentTimeline)
                        ]
                    )
                    reviewCard(
                        title: "Details",
                        rows: [
                            ("Description", draft.description),
                            ("Images attached", selectedImageDataList.isEmpty ? "0" : "\(selectedImageDataList.count)"),
                            ("Video attached", selectedVideoData == nil ? "No" : "Yes")
                        ]
                    )
                }
            }
        }
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
            .background(AuthTheme.primaryPink, in: Capsule())
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
            return !draft.title.isEmpty && !draft.category.isEmpty && !draft.amount.isEmpty
        case 1:
            return !draft.interestRate.isEmpty && !draft.repaymentTimeline.isEmpty
        case 2:
            return !draft.description.isEmpty
        default:
            return true
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
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1.5)
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1.5)
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
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                    Label(selectedVideoData == nil ? "Upload video (max 1)" : "Change video", systemImage: "video")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AuthTheme.fieldBorder, lineWidth: 1.5)
        )
    }

    private func reviewCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top) {
                    Text(rows[index].0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rows[index].1.isEmpty ? "-" : rows[index].1)
                        .font(.subheadline)
                        .multilineTextAlignment(.trailing)
                }
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.03))
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
}

