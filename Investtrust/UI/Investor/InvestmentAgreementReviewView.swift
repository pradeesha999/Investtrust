import SwiftUI

// MOA review and signing screen.
// Shows the frozen deal terms, a signature pad for drawing, and submits the signature image when the user signs.
struct InvestmentAgreementReviewView: View {
    @Environment(AuthService.self) private var auth

    let investment: InvestmentListing
    var canSign: Bool = true              // when false the signing footer is hidden (read-only mode)
    var onSign: (Data) async throws -> Void
    var onDidFinishSigning: (() -> Void)? = nil  // called after a successful signing, before dismiss

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

                    if let errorText, !errorText.isEmpty {
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

            Text("Binding snapshot captured when this request was accepted.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            termsSection("Parties & deal") {
                Group {
                    row("Opportunity", agreement.opportunityTitle)
                    row("Investor", agreement.investorName)
                    row("Seeker", agreement.seekerName)
                    row("Amount (LKR)", formatLKR(agreement.investmentAmount))
                    row("Type", agreement.investmentType.displayName)
                    row("Agreement ID", agreement.agreementId)
                    row("Prepared on", investment.agreementGeneratedAt.map(formatMediumDate) ?? "—")
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

            termsSection("Financial snapshot") {
                financialSnapshot(agreement: agreement)
            }

            termsSection("Commitments") {
                let t = agreement.termsSnapshot
                let freq = (t.repaymentFrequency ?? .monthly).displayName
                let timeline = t.repaymentTimelineMonths.map { "\($0) months" } ?? "agreed timeline"
                bullet("Repayment duty", "Seeker agrees to repay principal and interest over \(timeline).")
                bullet("Schedule adherence", "Payments are expected on each \(freq.lowercased()) due date.")
                bullet("Late handling", "Missed due dates may move the deal to defaulted status after grace checks.")
                bullet("Change control", "Any term changes must be agreed by all required signers in app.")
                bullet("Evidence trail", "All signatures, timelines, and term snapshots remain stored with this agreement for auditability.")
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
            }
        }
    }

    @ViewBuilder
    private func financialSnapshot(agreement: InvestmentAgreementSnapshot) -> some View {
        let amount = agreement.investmentAmount
        let t = agreement.termsSnapshot
        switch agreement.investmentType {
        case .loan:
            if let rate = t.interestRate,
               let months = t.repaymentTimelineMonths,
               months > 0,
               let outcome = OpportunityFinancialPreview.loanMoneyOutcome(
                principal: amount,
                annualRatePercent: rate,
                termMonths: months,
                plan: LoanRepaymentPlan.from(t.repaymentFrequency)
               ) {
                bullet("Principal", "LKR \(formatLKR(amount))")
                bullet("Estimated total payable", "LKR \(formatLKR(outcome.totalRepayable))")
                bullet("Estimated investor gain", "LKR \(formatLKR(outcome.interestAmount))")
                if let firstDue = outcome.firstInstallmentDue {
                    bullet("First due date", formatMediumDate(firstDue))
                }
                if let maturity = outcome.maturityDue {
                    bullet("Maturity date", formatMediumDate(maturity))
                }
            } else {
                bullet("Principal", "LKR \(formatLKR(amount))")
                Text("Detailed projection becomes available once timeline and rate are finalized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .equity:
            bullet("Committed capital", "LKR \(formatLKR(amount))")
            if let p = t.equityPercentage {
                bullet("Equity allocated", String(format: "%.1f%%", p))
            }
            if let v = t.businessValuation {
                bullet("Business valuation", "LKR \(formatLKR(v))")
            }
            Text("Returns depend on growth milestones and exit outcomes rather than fixed repayment.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
