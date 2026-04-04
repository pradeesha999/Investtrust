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

    @State private var draft = OpportunityDraft()
    @State private var currentStep = 0
    @State private var showSavedAlert = false
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var imagePickerItems: [PhotosPickerItem] = []
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var selectedImageDataList: [Data] = []
    @State private var selectedVideoData: Data?
    @State private var videoPickerError: String?
    @State private var selectedImages: [Image] = []

    private let steps = ["Basics", "Terms", "Details", "Review"]

    var onSubmit: (OpportunityDraft, [Data], Data?) async throws -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        progressHeader

                        Group {
                            switch currentStep {
                            case 0: basicStep
                            case 1: termsStep
                            case 2: detailsStep
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
                        .fill(AppTheme.accent)
                        .frame(width: max(14, geo.size.width * progress), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
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
        .padding(AppTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .fill(AppTheme.secondaryFill)
        )
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
}

