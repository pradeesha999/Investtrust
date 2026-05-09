import PhotosUI
import SwiftUI
import VisionKit

/// Seeker actions for one installment: confirm receipt + payment slip (camera or photo library).
/// Mirrors the flow in `LoanRepaymentScheduleView` so the listing detail screen can offer the same actions.
struct SeekerLoanPaymentConfirmBlock: View {
    let investment: InvestmentListing
    let installmentNo: Int
    var onRefresh: () async -> Void

    @Environment(AuthService.self) private var auth

    @State private var busy = false
    @State private var actionError: String?
    @State private var showDocCamera = false
    @State private var showLibrarySheet = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var previewProofURL: String?

    private let service = InvestmentService()

    private var row: LoanInstallment? {
        investment.loanInstallments.first { $0.installmentNo == installmentNo }
    }

    private var nextOpenInstallmentNo: Int? {
        investment.loanInstallments
            .filter { $0.status != .confirmed_paid }
            .sorted { $0.dueDate < $1.dueDate }
            .first?
            .installmentNo
    }

    private var isSeeker: Bool {
        guard let uid = auth.currentUserID, let sid = investment.seekerId else { return false }
        return uid == sid
    }

    var body: some View {
        Group {
            if let row, isSeeker, investment.loanRepaymentsUnlocked, row.status != .confirmed_paid {
                VStack(alignment: .leading, spacing: 12) {
                    if installmentNo == nextOpenInstallmentNo {
                        Label("Current cycle", systemImage: "circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(auth.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(auth.accentColor.opacity(0.12), in: Capsule())
                    } else {
                        Label("Locked: complete installment #\(nextOpenInstallmentNo ?? installmentNo) first", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    if !row.seekerProofImageURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your proof")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(row.seekerProofImageURLs, id: \.self) { url in
                                        Button {
                                            previewProofURL = url
                                        } label: {
                                            StorageBackedAsyncImage(reference: url, height: 92, cornerRadius: 10, feedThumbnail: true)
                                                .frame(width: 92, height: 92)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if row.status == .disputed, let reason = row.latestDisputeReason, !reason.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Investor reported not received")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    }

                    Button {
                        Task { await markReceived() }
                    } label: {
                        Group {
                            if busy {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else {
                                Text("Confirm payment sent")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                    .disabled(busy || installmentNo != nextOpenInstallmentNo || row.seekerProofImageURLs.isEmpty)

                    Button {
                        showLibrarySheet = true
                    } label: {
                        Label("Upload proof from photos", systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                    .disabled(busy || installmentNo != nextOpenInstallmentNo)

                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            showDocCamera = true
                        } label: {
                            Label("Scan proof with camera", systemImage: "doc.viewfinder")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(auth.accentColor)
                        .disabled(busy || installmentNo != nextOpenInstallmentNo)
                    }
                }
                .sheet(isPresented: $showLibrarySheet) {
                    libraryPickerSheet
                }
                .sheet(isPresented: Binding(
                    get: { previewProofURL != nil },
                    set: { if !$0 { previewProofURL = nil } }
                )) {
                    NavigationStack {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            if let previewProofURL {
                                StorageBackedAsyncImage(reference: previewProofURL, height: min(UIScreen.main.bounds.height * 0.72, 560), cornerRadius: 14, feedThumbnail: false)
                                    .padding(.horizontal, AppTheme.screenPadding)
                            }
                        }
                        .navigationTitle("Proof image")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .fullScreenCover(isPresented: $showDocCamera) {
                    documentCameraCover
                }
                .alert("Something went wrong", isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )) {
                    Button("OK") { actionError = nil }
                } message: {
                    Text(actionError ?? "")
                }
            }
        }
    }

    private var libraryPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Text("Choose from library")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(auth.accentColor)
            }
            .padding(AppTheme.screenPadding)
            .navigationTitle("Payment slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        libraryItem = nil
                        showLibrarySheet = false
                    }
                }
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                showLibrarySheet = false
                Task {
                    await handlePickedPhoto(item: item)
                    await MainActor.run { libraryItem = nil }
                }
            }
        }
    }

    @ViewBuilder
    private var documentCameraCover: some View {
        if VNDocumentCameraViewController.isSupported {
            DocumentCameraView { images in
                showDocCamera = false
                Task {
                    await uploadScannedPages(images)
                }
            }
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Scanner unavailable",
                    systemImage: "doc.viewfinder",
                    description: Text("Document scanning isn’t supported on this device. Use “Upload from photos” instead.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showDocCamera = false }
                    }
                }
            }
        }
    }

    private func markReceived() async {
        guard let uid = auth.currentUserID else { return }
        busy = true
        defer { busy = false }
        do {
            try await service.markLoanInstallmentReceivedBySeeker(
                investmentId: investment.id,
                installmentNo: installmentNo,
                userId: uid
            )
            await onRefresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func handlePickedPhoto(item: PhotosPickerItem) async {
        guard let uid = auth.currentUserID else { return }
        busy = true
        defer { busy = false }
        guard let raw = try? await item.loadTransferable(type: Data.self), !raw.isEmpty else {
            actionError = "Couldn’t read that photo. Try another image."
            return
        }
        let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: raw)
        guard !jpeg.isEmpty else {
            actionError = "Couldn’t convert that photo. Try another image."
            return
        }
        do {
            try await service.attachLoanInstallmentProof(
                investmentId: investment.id,
                installmentNo: installmentNo,
                userId: uid,
                imageJPEG: jpeg
            )
            await onRefresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }

    private func uploadScannedPages(_ chunks: [Data]) async {
        guard let uid = auth.currentUserID else { return }
        for chunk in chunks {
            busy = true
            let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: chunk)
            guard !jpeg.isEmpty else {
                actionError = "Couldn’t read a scanned page. Try again."
                continue
            }
            do {
                try await service.attachLoanInstallmentProof(
                    investmentId: investment.id,
                    installmentNo: installmentNo,
                    userId: uid,
                    imageJPEG: jpeg
                )
            } catch {
                actionError = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
            }
        }
        busy = false
        await onRefresh()
    }
}
