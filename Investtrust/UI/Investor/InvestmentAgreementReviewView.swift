import SwiftUI

/// Review MOA terms, draw a signature, and submit (uploads PNG + finalizes PDF when both parties have signed).
///
/// The signature panel uses **local `@State` only** (not `ObservableObject`) and sits **outside** the terms
/// `ScrollView` so SwiftUI does not rebuild a huge `TupleView` on every touch — that prevented stack overflow
/// (see `ModifiedContent._makeViewList` recursion in crash reports).
struct InvestmentAgreementReviewView: View {
    @Environment(AuthService.self) private var auth

    let investment: InvestmentListing
    /// When false, the footer signing action is hidden (read-only view).
    var canSign: Bool = true
    var onSign: (Data) async throws -> Void
    /// Called on the main actor after a **successful** sign, before this screen dismisses (e.g. close a requests sheet underneath).
    var onDidFinishSigning: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isSigning = false
    @State private var errorText: String?
    @State private var pdfSheet: MOAPDFSheetItem?
    @State private var pdfLoading = false
    @State private var pdfError: String?

    private let investmentService = InvestmentService()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    termsScrollContent

                    if let errorText, !canSign {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(AppTheme.screenPadding)
            }
            .background(Color(.systemGroupedBackground))

            if canSign {
                AgreementSignaturePanel(
                    accentColor: auth.accentColor,
                    agreementMissing: investment.agreement == nil,
                    isSigning: $isSigning,
                    errorText: $errorText,
                    onSign: { png in
                        try await onSign(png)
                        onDidFinishSigning?()
                        dismiss()
                    }
                )
                .padding(AppTheme.screenPadding)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Review agreement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .disabled(isSigning)
            }
        }
        .sheet(item: $pdfSheet) { item in
            MOAPDFViewerSheet(pdfData: item.data, filename: item.filename)
        }
    }

    @ViewBuilder
    private var termsScrollContent: some View {
        if let agreement = investment.agreement {
            Text("Memorandum of agreement")
                .font(.title3.weight(.bold))

            Text("Snapshot at acceptance.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            termsSection("Parties & deal") {
                Group {
                    row("Opportunity", agreement.opportunityTitle)
                    row("Investor", agreement.investorName)
                    row("Seeker", agreement.seekerName)
                    row("Amount (LKR)", formatLKR(agreement.investmentAmount))
                    row("Type", agreement.investmentType.displayName)
                }
                .font(.subheadline)
            }

            termsSection("Signing progress") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(investment.agreementSignedCount)/\(investment.agreementRequiredSignerCount) completed")
                        .font(.subheadline.weight(.semibold))
                    if !agreement.participants.isEmpty {
                        ForEach(Array(agreement.participants.enumerated()), id: \.offset) { _, participant in
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: participant.isSigned ? "checkmark.seal.fill" : "clock.badge.questionmark.fill")
                                    .foregroundStyle(participant.isSigned ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(participant.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(participant.signerRole == .seeker ? "Seeker" : "Investor")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(participant.signedAt.map(formatMediumDate) ?? "Pending")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(participant.isSigned ? .green : .secondary)
                            }
                        }
                    }
                }
            }

            termsSection("Terms") {
                termsBody(agreement: agreement, type: agreement.investmentType)
            }

            termsSection("Commitments") {
                let t = agreement.termsSnapshot
                let freq = (t.repaymentFrequency ?? .monthly).displayName
                let timeline = t.repaymentTimelineMonths.map { "\($0) months" } ?? "agreed timeline"
                bullet("Repayment duty", "Seeker agrees to repay principal and interest over \(timeline).")
                bullet("Schedule adherence", "Payments are expected on each \(freq.lowercased()) due date.")
                bullet("Late handling", "Missed due dates may move the deal to defaulted status after grace checks.")
                bullet("Change control", "Any term changes must be agreed by all required signers in app.")
            }

            if let gen = investment.agreementGeneratedAt {
                Text("Agreement prepared \(formatMediumDate(gen))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()
            Button {
                Task { await openMemorandumPDF() }
            } label: {
                HStack {
                    if pdfLoading {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                            .font(.body.weight(.semibold))
                    }
                    Text("View memorandum PDF")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(pdfLoading || investment.agreement == nil)

            if let pdfError, !pdfError.isEmpty {
                Text(pdfError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } else {
            Text("Agreement details are not available for this request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func openMemorandumPDF() async {
        pdfError = nil
        guard investment.agreement != nil else {
            pdfError = "Memorandum isn’t available yet."
            return
        }
        pdfLoading = true
        defer { pdfLoading = false }
        do {
            let data = try await investmentService.buildMOAPDFDocumentData(for: investment)
            let name = "Investtrust-MOA-\(investment.agreement?.agreementId ?? investment.id).pdf"
            await MainActor.run {
                pdfSheet = MOAPDFSheetItem(data: data, filename: name)
            }
        } catch let invErr as InvestmentService.InvestmentServiceError {
            await MainActor.run { pdfError = invErr.localizedDescription }
        } catch {
            await MainActor.run { pdfError = error.localizedDescription }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value.isEmpty ? "—" : value)
                .font(.body.weight(.medium))
        }
    }

    private func termsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func termsBody(agreement: InvestmentAgreementSnapshot, type: InvestmentType) -> some View {
        let t = agreement.termsSnapshot
        VStack(alignment: .leading, spacing: 10) {
            Text("Terms snapshot")
                .font(.headline)
            switch type {
            case .loan:
                bullet("Interest", "\(formatRate(t.interestRate ?? 0))%")
                if let m = t.repaymentTimelineMonths { bullet("Timeline", "\(m) months") }
                bullet("Frequency", (t.repaymentFrequency ?? .monthly).displayName)
            case .equity:
                if let p = t.equityPercentage { bullet("Equity", String(format: "%.1f%%", p)) }
                if let v = t.businessValuation { bullet("Valuation (LKR)", formatLKR(v)) }
                if let e = t.exitPlan, !e.isEmpty { bullet("Exit plan", e) }
            case .revenue_share:
                if let p = t.revenueSharePercent { bullet("Revenue share", String(format: "%.1f%%", p)) }
                if let a = t.targetReturnAmount { bullet("Target return (LKR)", formatLKR(a)) }
                if let m = t.maxDurationMonths { bullet("Max duration", "\(m) mo") }
            case .project:
                bullet("Return type", t.expectedReturnType?.rawValue.capitalized ?? "—")
                if let v = t.expectedReturnValue, !v.isEmpty { bullet("Expected return", v) }
                if let d = t.completionDate { bullet("Completion", formatMediumDate(d)) }
            case .custom:
                if let s = t.customTermsSummary, !s.isEmpty {
                    Text(s)
                        .font(.body)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bullet(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            VStack(alignment: .leading, spacing: 2) {
                Text(k)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(v)
                    .font(.subheadline)
            }
        }
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) { return String(Int(rate)) }
        return String(rate)
    }

    private func formatLKR(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }

    private func formatMediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }
}
