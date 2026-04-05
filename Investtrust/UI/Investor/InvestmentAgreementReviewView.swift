import SwiftUI

/// Simple review + timestamp “signature” for the structured MOA on the investment document.
struct InvestmentAgreementReviewView: View {
    let investment: InvestmentListing
    /// When false, the footer signing action is hidden (read-only view).
    var canSign: Bool = true
    var onSign: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSigning = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let agreement = investment.agreement {
                        Text("Memorandum of agreement")
                            .font(.title3.weight(.bold))

                        Text("Snapshot at acceptance — terms may differ from the live listing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Group {
                            row("Opportunity", agreement.opportunityTitle)
                            row("Investor", agreement.investorName)
                            row("Seeker", agreement.seekerName)
                            row("Amount (LKR)", formatLKR(agreement.investmentAmount))
                            row("Type", agreement.investmentType.displayName)
                        }
                        .font(.subheadline)

                        Divider()

                        termsBody(agreement: agreement, type: agreement.investmentType)

                        if let gen = investment.agreementGeneratedAt {
                            Text("Agreement prepared \(Self.mediumDate(gen))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("Agreement details are not available for this request.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(AppTheme.screenPadding)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review agreement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isSigning)
                }
            }
            safeAreaInset(edge: .bottom) {
                Group {
                    if canSign {
                        VStack(spacing: 0) {
                            Divider()
                            Button {
                                Task { await sign() }
                            } label: {
                                if isSigning {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                } else {
                                    Text("Agree & sign")
                                        .font(.headline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                            }
                            .buttonStyle(.plain)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                            .foregroundStyle(.white)
                            .disabled(isSigning || investment.agreement == nil)
                            .padding(AppTheme.screenPadding)
                        }
                        .background(.ultraThinMaterial)
                    }
                }
            }
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
                bullet("Frequency", (t.repaymentFrequency ?? .monthly).rawValue.capitalized)
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
                if let d = t.completionDate { bullet("Completion", Self.mediumDate(d)) }
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

    private func sign() async {
        errorText = nil
        isSigning = true
        defer { isSigning = false }
        do {
            try await onSign()
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                if let le = error as? LocalizedError, let d = le.errorDescription {
                    errorText = d
                } else {
                    errorText = (error as NSError).localizedDescription
                }
            }
        }
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }
}
