import PhotosUI
import SwiftUI
import VisionKit

struct RevenueShareScheduleView: View {
    let investment: InvestmentListing
    var currentUserId: String?
    var onRefresh: () async -> Void

    @Environment(AuthService.self) private var auth

    @State private var busyPeriod: Int?
    @State private var actionError: String?
    @State private var declarationInput: String = ""
    @State private var declaringPeriodNo: Int?
    @State private var showLibrarySheet = false
    @State private var showDocCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var proofTargetPeriodNo: Int?

    private let service = InvestmentService()

    private var sorted: [RevenueSharePeriod] {
        investment.revenueSharePeriods.sorted { $0.periodNo < $1.periodNo }
    }

    private var isSeeker: Bool { currentUserId == investment.seekerId }
    private var isInvestor: Bool { currentUserId == investment.investorId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.stackSpacing) {
                ForEach(sorted) { row in
                    periodCard(row)
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Revenue share")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showLibrarySheet) {
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Label("Choose from library", systemImage: "photo")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
            }
            .presentationDetents([.height(180)])
            .onChange(of: libraryItem) { _, item in
                guard let item, let no = proofTargetPeriodNo else { return }
                showLibrarySheet = false
                Task {
                    await handlePickedPhoto(item: item, periodNo: no)
                    await MainActor.run { libraryItem = nil }
                }
            }
        }
        .fullScreenCover(isPresented: $showDocCamera) {
            DocumentCameraView { images in
                showDocCamera = false
                guard let no = proofTargetPeriodNo else { return }
                Task { await uploadScannedPages(images, periodNo: no) }
            }
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

    @ViewBuilder
    private func periodCard(_ row: RevenueSharePeriod) -> some View {
        let seekerCanDeclare = isSeeker && row.status == .awaiting_declaration
        let seekerCanMarkSent = isSeeker && row.status != .confirmed_paid && row.seekerMarkedSentAt == nil
        let investorCanConfirm = isInvestor && row.status != .confirmed_paid && row.investorMarkedReceivedAt == nil

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Period #\(row.periodNo)")
                    .font(.headline)
                Spacer()
                Text(statusTitle(row.status))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(row.status).opacity(0.16), in: Capsule())
                    .foregroundStyle(statusColor(row.status))
            }

            Text("\(mediumDate(row.startDate)) - \(mediumDate(row.endDate))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let revenue = row.declaredRevenue {
                metaLine("Declared revenue", "LKR \(formatAmt(revenue))")
            }
            if let expected = row.expectedShareAmount {
                metaLine("Expected share due", "LKR \(formatAmt(expected))")
            }
            if let paid = row.actualPaidAmount {
                metaLine("Paid amount", "LKR \(formatAmt(paid))")
            }
            if let sent = row.seekerMarkedSentAt {
                metaLine("Seeker confirmed sent", mediumDate(sent))
            }
            if let received = row.investorMarkedReceivedAt {
                metaLine("Investor confirmed received", mediumDate(received))
            }

            proofThumbs(row)

            if seekerCanDeclare {
                HStack(spacing: 8) {
                    TextField("Revenue this period", text: Binding(
                        get: { declaringPeriodNo == row.periodNo ? declarationInput : "" },
                        set: { newValue in
                            declaringPeriodNo = row.periodNo
                            declarationInput = newValue
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                    Button("Declare") {
                        Task { await declareRevenue(for: row.periodNo) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                    .disabled(busyPeriod != nil)
                }
            }

            if seekerCanMarkSent {
                Button("Confirm payment sent") {
                    Task { await markSent(row.periodNo) }
                }
                .buttonStyle(.borderedProminent)
                .tint(auth.accentColor)
                .disabled(busyPeriod != nil || ((row.expectedShareAmount ?? 0) > 0 && row.seekerProofImageURLs.isEmpty))
            }

            if investorCanConfirm {
                Button("Confirm payment received") {
                    Task { await markReceived(row.periodNo) }
                }
                .buttonStyle(.borderedProminent)
                .tint(auth.accentColor)
                .disabled(busyPeriod != nil || row.seekerMarkedSentAt == nil)
            }

            if (isSeeker && row.seekerMarkedSentAt == nil) || (isInvestor && row.investorMarkedReceivedAt == nil) {
                Menu {
                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            proofTargetPeriodNo = row.periodNo
                            showDocCamera = true
                        } label: {
                            Label("Scan proof", systemImage: "doc.viewfinder")
                        }
                    }
                    Button {
                        proofTargetPeriodNo = row.periodNo
                        showLibrarySheet = true
                    } label: {
                        Label("Upload proof", systemImage: "photo")
                    }
                } label: {
                    Label(isInvestor ? "Attach receipt proof" : "Attach payment slip", systemImage: "paperclip")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func proofThumbs(_ row: RevenueSharePeriod) -> some View {
        if !row.seekerProofImageURLs.isEmpty || !row.investorProofImageURLs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !row.seekerProofImageURLs.isEmpty {
                    proofStrip(title: "Seeker slips", urls: row.seekerProofImageURLs)
                }
                if !row.investorProofImageURLs.isEmpty {
                    proofStrip(title: "Investor receipts", urls: row.investorProofImageURLs)
                }
            }
        }
    }

    private func proofStrip(title: String, urls: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        StorageBackedAsyncImage(reference: url, height: 72, cornerRadius: 10, feedThumbnail: true)
                            .frame(width: 72, height: 72)
                    }
                }
            }
        }
    }

    private func declareRevenue(for periodNo: Int) async {
        guard let uid = currentUserId else { return }
        let parsed = Double(declarationInput.replacingOccurrences(of: ",", with: "")) ?? -1
        busyPeriod = periodNo
        defer { busyPeriod = nil }
        do {
            try await service.declareRevenueForPeriod(
                investmentId: investment.id,
                periodNo: periodNo,
                declaredRevenue: parsed,
                userId: uid
            )
            declaringPeriodNo = nil
            declarationInput = ""
            await onRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func markSent(_ periodNo: Int) async {
        guard let uid = currentUserId else { return }
        busyPeriod = periodNo
        defer { busyPeriod = nil }
        do {
            try await service.markRevenueSharePeriodPaidBySeeker(
                investmentId: investment.id,
                periodNo: periodNo,
                userId: uid
            )
            await onRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func markReceived(_ periodNo: Int) async {
        guard let uid = currentUserId else { return }
        busyPeriod = periodNo
        defer { busyPeriod = nil }
        do {
            try await service.markRevenueSharePeriodReceivedByInvestor(
                investmentId: investment.id,
                periodNo: periodNo,
                userId: uid
            )
            await onRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func handlePickedPhoto(item: PhotosPickerItem, periodNo: Int) async {
        guard let uid = currentUserId else { return }
        busyPeriod = periodNo
        defer { busyPeriod = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self), !raw.isEmpty else {
            actionError = "Could not read that photo."
            return
        }
        let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: raw)
        guard !jpeg.isEmpty else {
            actionError = "Could not convert that photo."
            return
        }
        do {
            try await service.attachRevenueSharePeriodProof(
                investmentId: investment.id,
                periodNo: periodNo,
                userId: uid,
                imageJPEG: jpeg
            )
            await onRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func uploadScannedPages(_ chunks: [Data], periodNo: Int) async {
        guard let uid = currentUserId else { return }
        for chunk in chunks {
            busyPeriod = periodNo
            let jpeg = ImageJPEGUploadPayload.jpegForUpload(from: chunk)
            guard !jpeg.isEmpty else { continue }
            do {
                try await service.attachRevenueSharePeriodProof(
                    investmentId: investment.id,
                    periodNo: periodNo,
                    userId: uid,
                    imageJPEG: jpeg
                )
            } catch {
                actionError = error.localizedDescription
            }
        }
        busyPeriod = nil
        await onRefresh()
    }

    private func statusTitle(_ s: RevenueSharePeriodStatus) -> String {
        switch s {
        case .awaiting_declaration: return "Awaiting declaration"
        case .awaiting_payment: return "Awaiting payment"
        case .awaiting_confirmation: return "Awaiting confirmation"
        case .confirmed_paid: return "Paid"
        case .disputed: return "Disputed"
        }
    }

    private func statusColor(_ s: RevenueSharePeriodStatus) -> Color {
        switch s {
        case .confirmed_paid: return .green
        case .awaiting_confirmation, .awaiting_payment: return .orange
        case .awaiting_declaration: return .secondary
        case .disputed: return .red
        }
    }

    private func metaLine(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            Spacer()
            Text(v).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private func formatAmt(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }
}
