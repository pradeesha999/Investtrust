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

    private let service = InvestmentService()

    private var row: LoanInstallment? {
        investment.loanInstallments.first { $0.installmentNo == installmentNo }
    }

    private var isSeeker: Bool {
        guard let uid = auth.currentUserID, let sid = investment.seekerId else { return false }
        return uid == sid
    }

    var body: some View {
        Group {
            if let row, isSeeker, investment.loanRepaymentsUnlocked, row.status != .confirmed_paid {
                VStack(alignment: .leading, spacing: 12) {
                    if !row.seekerProofImageURLs.isEmpty {
                        Label("\(row.seekerProofImageURLs.count) payment slip(s) attached", systemImage: "paperclip.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
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
                    .disabled(busy || (row.seekerProofImageURLs.isEmpty && row.investorMarkedPaidAt == nil))

                    Menu {
                        if VNDocumentCameraViewController.isSupported {
                            Button {
                                showDocCamera = true
                            } label: {
                                Label("Scan slip with camera", systemImage: "doc.viewfinder")
                            }
                        }
                        Button {
                            showLibrarySheet = true
                        } label: {
                            Label("Upload from photos", systemImage: "photo.on.rectangle.angled")
                        }
                    } label: {
                        Label("Attach payment slip", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(auth.accentColor)
                    .disabled(busy)

                    Text("Attach your bank receipt or transfer screenshot, then confirm you sent this installment. The investor will review and confirm they received it (they can add a receipt photo too).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .sheet(isPresented: $showLibrarySheet) {
                    libraryPickerSheet
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
                Text("Choose a photo of your payment slip or transfer confirmation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Label("Choose from library", systemImage: "photo.on.rectangle.angled")
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
