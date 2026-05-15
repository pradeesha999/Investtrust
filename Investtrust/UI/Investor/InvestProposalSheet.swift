import SwiftUI
import UIKit

// The "Invest" bottom sheet — the investor confirms at the listing's stated terms
// or switches to "Make Offer" to propose custom amount, rate, and term
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

    let opportunity: OpportunityListing
    let investorId: String
    // Called on the main actor after a successful submission + chat card delivery.
    // Receives nothing — the parent should refresh its own view state via its own service.
    let onSubmitted: () -> Void
    private let lockToOfferMode: Bool
    private let lockToStandardMode: Bool

    private let investmentService = InvestmentService()
    private let chatService = ChatService()

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
    // One-shot guard: SwiftUI may run `.onAppear` more than once. Without this, typed values get
    // wiped back to listing defaults (so 250k submits as 300k).
    @State private var didSeedListingDefaults = false

    init(
        opportunity: OpportunityListing,
        investorId: String,
        preferOfferMode: Bool = false,
        lockToOfferMode: Bool = false,
        lockToStandardMode: Bool = false,
        onSubmitted: @escaping () -> Void
    ) {
        self.opportunity = opportunity
        self.investorId = investorId
        self.lockToOfferMode = lockToOfferMode
        self.lockToStandardMode = lockToStandardMode
        self.onSubmitted = onSubmitted
        // Negotiable listings ALWAYS use the offer form. Non-negotiable stay on the standard form.
        _requestMode = State(initialValue: (preferOfferMode || opportunity.isNegotiable) ? .offer : .standard)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(introCopy)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if opportunity.isNegotiable {
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
            .scrollDismissesKeyboard(.immediately)
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
            guard !didSeedListingDefaults else { return }
            resetOfferFieldsToListingDefaults()
            didSeedListingDefaults = true
        }
    }

    private func listingTicketAmount() -> Double {
        let cap = max(1, opportunity.maximumInvestors ?? 1)
        if cap > 1 {
            return InvestmentService.fixedEqualSplitAmount(total: opportunity.amountRequested, investors: cap)
        }
        return opportunity.amountRequested
    }

    // True when parsed offer fields are not the same as the listing (used to avoid losing typed terms if the segmented control was on “Invest now”).
    private var parsedOfferFieldsDifferFromListing: Bool {
        guard opportunity.isNegotiable else { return false }
        guard let amt = parsedAmount, let rate = parsedInterestRate, let tm = parsedTimelineMonths else { return false }
        let listingAmt = listingTicketAmount()
        let listingTm = max(1, opportunity.repaymentTimelineMonths)
        let listingRate = opportunity.interestRate
        return abs(amt - listingAmt) > 0.01
            || abs(rate - listingRate) > 0.0001
            || tm != listingTm
    }

    private func resetOfferFieldsToListingDefaults() {
        offerAmountText = Self.formatLKR(listingTicketAmount())
        offerRateText = opportunity.interestRate > 0 ? String(format: "%.2f", opportunity.interestRate) : ""
        offerTimelineText = "\(max(1, opportunity.repaymentTimelineMonths))"
        offerNote = ""
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
        await MainActor.run(resultType: Void.self) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if !opportunity.isNegotiable {
                guard confirmStandardRequest else {
                    submitError = "Please confirm before sending the request."
                    return
                }
            }
            let amt = parsedAmount ?? listingTicketAmount()
            let rate = parsedInterestRate ?? opportunity.interestRate
            let tm = parsedTimelineMonths ?? max(1, opportunity.repaymentTimelineMonths)
            guard amt > 0, tm > 0 else {
                submitError = "Please enter valid offer terms."
                return
            }
            let trimmedNote = offerNote.trimmingCharacters(in: .whitespacesAndNewlines)
            let negotiated = opportunity.isNegotiable

            print("[OFFER] sheet.submit amt=\(amt) rate=\(rate) months=\(tm) note='\(trimmedNote)' negotiated=\(negotiated)")

            let created = try await investmentService.createOrUpdateOfferRequest(
                opportunity: opportunity,
                investorId: investorId,
                proposedAmount: amt,
                proposedInterestRate: rate,
                proposedTimelineMonths: tm,
                description: trimmedNote,
                source: .detail_sheet
            )
            print("[OFFER] sheet.persisted invId=\(created.id) kind=\(created.requestKind.rawValue) amt=\(created.investmentAmount)")

            let requestKindLabel = negotiated ? "Offer request" : "Investment request"
            let noteText = trimmedNote.isEmpty
                ? (negotiated ? "Negotiated offer from listing." : "Default investment request from listing.")
                : trimmedNote
            let amountText = Self.lkrFormat(created.effectiveAmount)
            let rateText = created.effectiveFinalInterestRate.map { String(format: "%.2f%%", $0) } ?? "—"
            let timelineText = created.effectiveFinalTimelineMonths.map { "\($0) months" } ?? "—"

            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opportunity.id,
                seekerId: opportunity.ownerId,
                investorId: investorId,
                opportunityTitle: opportunity.title
            )
            let snapshot = InvestmentRequestSnapshot(
                investmentId: created.id,
                opportunityId: opportunity.id,
                title: opportunity.title,
                amountText: amountText,
                interestRateText: rateText,
                timelineText: timelineText,
                note: noteText,
                requestKindLabel: requestKindLabel
            )
            _ = try await chatService.sendInvestmentRequestCard(
                chatId: chatId,
                senderId: investorId,
                snapshot: snapshot
            )

            await MainActor.run(resultType: Void.self) {
                onSubmitted()
                dismiss()
            }
        } catch {
            await MainActor.run(resultType: Void.self) {
                if let le = error as? LocalizedError, let d = le.errorDescription, !d.isEmpty {
                    submitError = d
                } else {
                    submitError = FirestoreUserFacingMessage.text(for: error)
                }
            }
        }
    }

    private static func lkrFormat(_ value: Double) -> String {
        let n = NSNumber(value: value)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        let s = f.string(from: n) ?? String(format: "%.2f", value)
        return "LKR \(s)"
    }
}
