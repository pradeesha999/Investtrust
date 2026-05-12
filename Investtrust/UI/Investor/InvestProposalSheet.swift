import SwiftUI

/// Confirms a standard investment request on the listing’s stated terms (no custom amount or checkboxes here—MOA covers legal acceptance).
struct InvestProposalSheet: View {
    private enum RequestMode: String, CaseIterable, Identifiable {
        case standard
        case offer

        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: return "Invest now"
            case .offer: return "Make offer"
            }
        }
    }

    enum Submission {
        case standardRequest
        case negotiatedOffer(amount: Double?, interestRate: Double, timelineMonths: Int, note: String)
    }

    let opportunity: OpportunityListing
    let onSubmit: (Submission) async throws -> Void
    private let lockToOfferMode: Bool
    private let lockToStandardMode: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var confirmStandardRequest = false
    @State private var showSubmitConfirmation = false
    @State private var requestMode: RequestMode = .standard
    @State private var offerAmountText = ""
    @State private var offerRateText = ""
    @State private var offerTimelineText = ""
    @State private var offerNote = ""

    init(
        opportunity: OpportunityListing,
        preferOfferMode: Bool = false,
        lockToOfferMode: Bool = false,
        lockToStandardMode: Bool = false,
        onSubmit: @escaping (Submission) async throws -> Void
    ) {
        self.opportunity = opportunity
        self.lockToOfferMode = lockToOfferMode
        self.lockToStandardMode = lockToStandardMode
        self.onSubmit = onSubmit
        _requestMode = State(initialValue: preferOfferMode ? .offer : .standard)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(introCopy)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if opportunity.isNegotiable && !lockToOfferMode && !lockToStandardMode {
                    Section("Choose action") {
                        Picker("Action", selection: $requestMode) {
                            ForEach(RequestMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if opportunity.isNegotiable && effectiveRequestMode == .offer {
                    Section("Negotiated terms") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Investment amount (LKR)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. 1,200,000", text: $offerAmountText)
                                .keyboardType(.numberPad)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Interest rate (%)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. 12", text: $offerRateText)
                                .keyboardType(.decimalPad)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Timeline (months)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. 12", text: $offerTimelineText)
                                .keyboardType(.numberPad)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Offer note (optional)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Any context for the seeker", text: $offerNote, axis: .vertical)
                                .lineLimit(1...3)
                        }
                    }
                } else {
                    Section("Listed terms") {
                        VStack(alignment: .leading, spacing: 8) {
                            termRow("Amount", value: listedAmountLine)
                            termRow("Interest rate", value: listedRateLine)
                            termRow("Timeline", value: listedTimelineLine)
                        }
                        if !opportunity.isNegotiable {
                            Toggle("I confirm I want to send a request on listed terms.", isOn: $confirmStandardRequest)
                        } else {
                            Text("Send a direct request on listed terms. You can switch to “Make offer” to propose different values.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let submitError {
                    Section {
                        Text(submitError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Investment request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(reviewButtonTitle) {
                            showSubmitConfirmation = true
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showSubmitConfirmation,
            titleVisibility: .visible
        ) {
            Button(confirmButtonTitle) {
                Task { await submit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .onAppear {
            let cap = max(1, opportunity.maximumInvestors ?? 1)
            let defaultOfferAmount: Double = cap > 1
                ? InvestmentService.fixedEqualSplitAmount(total: opportunity.amountRequested, investors: cap)
                : opportunity.amountRequested
            offerAmountText = Self.formatLKR(defaultOfferAmount)
            offerRateText = opportunity.interestRate > 0 ? String(format: "%.2f", opportunity.interestRate) : ""
            offerTimelineText = "\(max(1, opportunity.repaymentTimelineMonths))"
        }
    }

    private var introCopy: String {
        let cap = max(1, opportunity.maximumInvestors ?? 1)
        if cap > 1 {
            let split = InvestmentService.fixedEqualSplitAmount(
                total: opportunity.amountRequested,
                investors: cap
            )
            let splitText = Self.formatLKR(split)
            return "You’re requesting to invest on this listing’s stated terms: \(opportunity.investmentType.displayName) — \(opportunity.termsSummaryLine). With \(cap) investors, each ticket is LKR \(splitText). The seeker can accept or decline. You’ll review and sign the memorandum of agreement if they accept."
        }
        let amt = Self.formatLKR(opportunity.amountRequested)
        return "You’re requesting to invest LKR \(amt) on this listing’s stated terms: \(opportunity.investmentType.displayName) — \(opportunity.termsSummaryLine). The seeker can accept or decline. You’ll review and sign the memorandum of agreement if they accept."
    }

    private static func formatLKR(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }

    private var canSubmit: Bool {
        if opportunity.isNegotiable, effectiveRequestMode == .offer {
            return parsedAmount != nil && parsedInterestRate != nil && parsedTimelineMonths != nil
        }
        if opportunity.isNegotiable {
            return true
        }
        return confirmStandardRequest
    }

    private var effectiveRequestMode: RequestMode {
        if lockToOfferMode { return .offer }
        if lockToStandardMode { return .standard }
        return requestMode
    }

    private var submitButtonTitle: String {
        if opportunity.isNegotiable {
            return effectiveRequestMode == .offer ? "Send offer request" : "Send investment request"
        }
        return "Send request"
    }

    private var reviewButtonTitle: String {
        effectiveRequestMode == .offer ? "Send offer" : "Review request"
    }

    private var confirmationTitle: String {
        effectiveRequestMode == .offer ? "Confirm offer details" : "Confirm investment request"
    }

    private var confirmButtonTitle: String {
        effectiveRequestMode == .offer ? "Send offer" : "Confirm and send"
    }

    private var confirmationMessage: String {
        if effectiveRequestMode == .offer {
            let amt = parsedAmount ?? 0
            let rate = parsedInterestRate ?? 0
            let tm = parsedTimelineMonths ?? 0
            return """
            Amount: LKR \(Self.formatLKR(amt))
            Rate: \(String(format: "%.2f", rate))%
            Timeline: \(tm) months
            """
        }
        return "You are requesting to invest on the listed terms for this opportunity."
    }

    private var listedAmountLine: String {
        let cap = max(1, opportunity.maximumInvestors ?? 1)
        if cap > 1 {
            let split = InvestmentService.fixedEqualSplitAmount(total: opportunity.amountRequested, investors: cap)
            return "LKR \(Self.formatLKR(split)) each (\(cap) investors)"
        }
        return "LKR \(Self.formatLKR(opportunity.amountRequested))"
    }

    private var listedRateLine: String {
        if opportunity.interestRate > 0 {
            return "\(String(format: "%.2f", opportunity.interestRate))%"
        }
        return "As listed"
    }

    private var listedTimelineLine: String {
        let months = max(1, opportunity.repaymentTimelineMonths)
        return "\(months) months"
    }

    @ViewBuilder
    private func termRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private var parsedAmount: Double? {
        let cleaned = offerAmountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var parsedInterestRate: Double? {
        let cleaned = offerRateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var parsedTimelineMonths: Int? {
        let digits = offerTimelineText.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private func submit() async {
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if opportunity.isNegotiable, effectiveRequestMode == .offer {
                guard let amt = parsedAmount, let rate = parsedInterestRate, let tm = parsedTimelineMonths else {
                    submitError = "Please enter valid offer terms."
                    return
                }
                try await onSubmit(.negotiatedOffer(
                    amount: amt,
                    interestRate: rate,
                    timelineMonths: tm,
                    note: offerNote.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            } else {
                guard opportunity.isNegotiable || confirmStandardRequest else {
                    submitError = "Please confirm before sending the request."
                    return
                }
                try await onSubmit(.standardRequest)
            }
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                if let le = error as? LocalizedError, let d = le.errorDescription {
                    submitError = d
                } else {
                    submitError = (error as NSError).localizedDescription
                }
            }
        }
    }
}
