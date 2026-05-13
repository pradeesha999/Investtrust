import CryptoKit
import PDFKit
import UIKit

/// Renders a printable, multi-page Memorandum of Agreement PDF (Core Graphics).
/// Layout is a flowing single-column document that auto-paginates so long terms / signatures never overflow.
enum MOAPDFBuilder {
    // MARK: - Page geometry (US Letter)
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let pageWidth = pageRect.width
    private static let pageHeight = pageRect.height
    private static let margin: CGFloat = 54
    private static let headerHeight: CGFloat = 96
    private static let footerHeight: CGFloat = 36
    private static let contentTop: CGFloat = headerHeight + 18
    private static let contentBottom: CGFloat = pageHeight - footerHeight - 12

    // MARK: - Palette
    private static let inkPrimary = UIColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 1)
    private static let inkSecondary = UIColor(red: 0.32, green: 0.36, blue: 0.42, alpha: 1)
    private static let inkMuted = UIColor(red: 0.50, green: 0.54, blue: 0.60, alpha: 1)
    private static let headerFill = UIColor(red: 0.11, green: 0.18, blue: 0.28, alpha: 1)
    private static let accent = UIColor(red: 0.78, green: 0.22, blue: 0.35, alpha: 1)
    private static let cardFill = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
    private static let cardStroke = UIColor(red: 0.86, green: 0.89, blue: 0.93, alpha: 1)
    private static let signatureLine = UIColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1)

    // MARK: - Public API

    static func buildPDF(
        agreement: InvestmentAgreementSnapshot,
        signaturesBySignerId: [String: UIImage]
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Memorandum of Agreement – \(agreement.opportunityTitle)",
            kCGPDFContextAuthor as String: "Investtrust",
            kCGPDFContextSubject as String: "Investment agreement between \(agreement.investorName) and \(agreement.seekerName)",
            kCGPDFContextCreator as String: "Investtrust iOS"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { pdfCtx in
            var state = RenderState(pdfCtx: pdfCtx, agreement: agreement)
            state.beginPage()

            drawTitleBlock(state: &state)

            drawSectionHeading("1.  Parties", state: &state)
            drawKeyValueTable(rows: partiesRows(agreement), state: &state)

            drawSectionHeading("2.  Agreement Reference", state: &state)
            drawKeyValueTable(rows: referenceRows(agreement), state: &state)

            drawSectionHeading("3.  Investment Summary", state: &state)
            drawKeyValueTable(rows: investmentSummaryRows(agreement), state: &state)

            if agreement.investmentType == .loan {
                drawSectionHeading("4.  Loan Terms", state: &state)
                drawKeyValueTable(rows: loanTermsRows(agreement), state: &state)

                if let schedule = loanRepaymentScheduleText(agreement) {
                    drawSectionHeading("5.  Repayment Schedule", state: &state)
                    drawParagraph(schedule, state: &state)
                }

                drawSectionHeading(loanCommitmentsHeading(agreement), state: &state)
                drawNumberedClauses(loanCommitments(agreement), state: &state)
            } else {
                drawSectionHeading("4.  Equity Terms", state: &state)
                drawKeyValueTable(rows: equityTermsRows(agreement), state: &state)

                if let venture = ventureProfileText(agreement) {
                    drawSectionHeading("5.  Venture Profile", state: &state)
                    drawParagraph(venture, state: &state)
                }

                drawSectionHeading(equityCommitmentsHeading(agreement), state: &state)
                drawNumberedClauses(equityCommitments(agreement), state: &state)
            }

            drawSectionHeading("\(nextSectionNumber(&state)).  General Provisions", state: &state)
            drawNumberedClauses(generalProvisions(), state: &state)

            drawSignatureSection(
                state: &state,
                signaturesBySignerId: signaturesBySignerId
            )

            finalizePages(pdfCtx: pdfCtx, totalPages: state.currentPage)
        }
    }

    /// Wraps `buildPDF` in a `PDFDocument` for `PDFView`.
    static func makePDFDocument(
        agreement: InvestmentAgreementSnapshot,
        signaturesBySignerId: [String: UIImage]
    ) -> PDFDocument? {
        let data = buildPDF(agreement: agreement, signaturesBySignerId: signaturesBySignerId)
        return PDFDocument(data: data)
    }

    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Render state / pagination

    private struct RenderState {
        let pdfCtx: UIGraphicsPDFRendererContext
        let agreement: InvestmentAgreementSnapshot
        var y: CGFloat = contentTop
        var currentPage: Int = 0
        var sectionCount: Int = 0

        mutating func beginPage() {
            pdfCtx.beginPage()
            currentPage += 1
            guard let cg = UIGraphicsGetCurrentContext() else { return }
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(pageRect)
            drawRunningHeader(cg: cg, agreement: agreement)
            drawRunningFooter(cg: cg, agreement: agreement, page: currentPage)
            y = contentTop
        }

        mutating func ensureSpace(_ needed: CGFloat) {
            if y + needed > contentBottom {
                beginPage()
            }
        }
    }

    private static func nextSectionNumber(_ state: inout RenderState) -> Int {
        state.sectionCount += 1
        return state.sectionCount + 5 // sections 1..5 already used above (4/5 vary by type)
    }

    // MARK: - Running header/footer

    private static func drawRunningHeader(cg: CGContext, agreement: InvestmentAgreementSnapshot) {
        cg.setFillColor(headerFill.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: pageWidth, height: headerHeight))

        cg.setFillColor(accent.cgColor)
        cg.fill(CGRect(x: 0, y: headerHeight, width: pageWidth, height: 3))

        let title = "Memorandum of Agreement"
        let subtitle = "Investtrust  •  \(agreement.investmentType.displayName) Investment"
        (title as NSString).draw(
            at: CGPoint(x: margin, y: 30),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        )
        (subtitle as NSString).draw(
            at: CGPoint(x: margin, y: 60),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
        )

        let agreementLabel = "Agreement \(shortHash(agreement.agreementId))"
        let dateLabel = "Prepared \(mediumDate(agreement.createdAt))"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85)
        ]
        let agreementSize = (agreementLabel as NSString).size(withAttributes: labelAttrs)
        let dateSize = (dateLabel as NSString).size(withAttributes: labelAttrs)
        (agreementLabel as NSString).draw(
            at: CGPoint(x: pageWidth - margin - agreementSize.width, y: 32),
            withAttributes: labelAttrs
        )
        (dateLabel as NSString).draw(
            at: CGPoint(x: pageWidth - margin - dateSize.width, y: 50),
            withAttributes: labelAttrs
        )
    }

    private static func drawRunningFooter(cg: CGContext, agreement: InvestmentAgreementSnapshot, page: Int) {
        let footerY = pageHeight - footerHeight
        cg.setFillColor(cardStroke.cgColor)
        cg.fill(CGRect(x: margin, y: footerY, width: pageWidth - margin * 2, height: 0.5))

        let left = "Terms hash \(shortHash(agreement.termsSnapshotHash))  •  v\(agreement.agreementVersion)"
        let leftAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: inkMuted
        ]
        (left as NSString).draw(
            at: CGPoint(x: margin, y: footerY + 10),
            withAttributes: leftAttrs
        )

        let right = "Page \(page)"
        let rightAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: inkSecondary
        ]
        let size = (right as NSString).size(withAttributes: rightAttrs)
        (right as NSString).draw(
            at: CGPoint(x: pageWidth - margin - size.width, y: footerY + 10),
            withAttributes: rightAttrs
        )
    }

    private static func finalizePages(pdfCtx: UIGraphicsPDFRendererContext, totalPages: Int) {
        // PDFKit doesn't let us rewrite earlier pages here, so the footer shows page index only.
        _ = pdfCtx
        _ = totalPages
    }

    // MARK: - Title block

    private static func drawTitleBlock(state: inout RenderState) {
        state.ensureSpace(140)
        let a = state.agreement

        let preamble = """
        This Memorandum of Agreement (\u{201C}Agreement\u{201D}) is entered into on \(mediumDate(a.createdAt)) \
        between \(a.investorName) (the \u{201C}Investor\u{201D}) and \(a.seekerName) (the \u{201C}Seeker\u{201D}) \
        in connection with the opportunity titled \u{201C}\(a.opportunityTitle)\u{201D}.
        """

        let dealBadge = "\(a.investmentType.displayName) Agreement"
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let badgeSize = (dealBadge as NSString).size(withAttributes: badgeAttrs)
        let badgeRect = CGRect(x: margin, y: state.y, width: badgeSize.width + 20, height: badgeSize.height + 8)
        if let cg = UIGraphicsGetCurrentContext() {
            cg.setFillColor(accent.cgColor)
            let path = UIBezierPath(roundedRect: badgeRect, cornerRadius: 4)
            cg.addPath(path.cgPath)
            cg.fillPath()
        }
        (dealBadge as NSString).draw(
            at: CGPoint(x: badgeRect.minX + 10, y: badgeRect.minY + 4),
            withAttributes: badgeAttrs
        )
        state.y += badgeRect.height + 14

        let heading = "“\(a.opportunityTitle)”"
        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: inkPrimary
        ]
        let headingHeight = (heading as NSString).boundingRect(
            with: CGSize(width: pageWidth - margin * 2, height: 200),
            options: [.usesLineFragmentOrigin],
            attributes: headingAttrs,
            context: nil
        ).height
        (heading as NSString).draw(
            with: CGRect(x: margin, y: state.y, width: pageWidth - margin * 2, height: headingHeight + 4),
            options: [.usesLineFragmentOrigin],
            attributes: headingAttrs,
            context: nil
        )
        state.y += headingHeight + 8

        drawParagraph(preamble, state: &state)
        state.y += 6
    }

    // MARK: - Sections

    private static func drawSectionHeading(_ title: String, state: inout RenderState) {
        state.ensureSpace(38)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: inkPrimary,
            .kern: 0.6
        ]
        (title.uppercased() as NSString).draw(
            at: CGPoint(x: margin, y: state.y),
            withAttributes: attrs
        )
        state.y += 18
        if let cg = UIGraphicsGetCurrentContext() {
            cg.setFillColor(accent.cgColor)
            cg.fill(CGRect(x: margin, y: state.y, width: 28, height: 2))
        }
        state.y += 10
    }

    private static func drawParagraph(_ text: String, state: inout RenderState) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.alignment = .justified
        para.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: inkSecondary,
            .paragraphStyle: para
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let contentWidth = pageWidth - margin * 2

        drawAttributedFlowing(attributed, width: contentWidth, state: &state)
        state.y += 8
    }

    private static func drawKeyValueTable(rows: [(String, String)], state: inout RenderState) {
        guard !rows.isEmpty else { return }
        let contentWidth = pageWidth - margin * 2
        let keyColumn: CGFloat = 170
        let valueColumn = contentWidth - keyColumn - 20

        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: inkMuted,
            .kern: 0.3
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: inkPrimary
        ]

        for (idx, row) in rows.enumerated() {
            let keyText = NSAttributedString(string: row.0.uppercased(), attributes: keyAttrs)
            let valueText = NSAttributedString(string: row.1, attributes: valueAttrs)
            let keyHeight = keyText.boundingRect(
                with: CGSize(width: keyColumn, height: 2000),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).height
            let valueHeight = valueText.boundingRect(
                with: CGSize(width: valueColumn, height: 2000),
                options: [.usesLineFragmentOrigin],
                context: nil
            ).height
            let rowHeight = max(keyHeight, valueHeight) + 14

            state.ensureSpace(rowHeight + 4)

            if idx % 2 == 0, let cg = UIGraphicsGetCurrentContext() {
                cg.setFillColor(cardFill.cgColor)
                cg.fill(CGRect(x: margin - 4, y: state.y - 2, width: contentWidth + 8, height: rowHeight))
            }

            keyText.draw(
                with: CGRect(x: margin, y: state.y + 4, width: keyColumn, height: keyHeight + 4),
                options: [.usesLineFragmentOrigin],
                context: nil
            )
            valueText.draw(
                with: CGRect(x: margin + keyColumn + 20, y: state.y + 2, width: valueColumn, height: valueHeight + 4),
                options: [.usesLineFragmentOrigin],
                context: nil
            )

            state.y += rowHeight
        }
        state.y += 10
    }

    private static func drawNumberedClauses(_ clauses: [String], state: inout RenderState) {
        let contentWidth = pageWidth - margin * 2
        let numberColumn: CGFloat = 22
        let textColumn = contentWidth - numberColumn

        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: accent
        ]
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.alignment = .justified
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: inkSecondary,
            .paragraphStyle: para
        ]

        for (i, clause) in clauses.enumerated() {
            let numberString = "\(i + 1)."
            let attributed = NSAttributedString(string: clause, attributes: bodyAttrs)

            var remaining = attributed
            var firstLine = true
            while remaining.length > 0 {
                let available = max(40, contentBottom - state.y)
                let widthToUse = firstLine ? textColumn : textColumn
                let xOffset = margin + numberColumn
                let (consumed, _) = breakAttributedString(remaining, width: widthToUse, maxHeight: available)
                if consumed.length == 0 {
                    state.beginPage()
                    continue
                }
                let usedHeight = consumed.boundingRect(
                    with: CGSize(width: widthToUse, height: 4000),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                ).height

                if firstLine {
                    (numberString as NSString).draw(
                        at: CGPoint(x: margin, y: state.y + 1),
                        withAttributes: numberAttrs
                    )
                    firstLine = false
                }

                consumed.draw(
                    with: CGRect(x: xOffset, y: state.y, width: widthToUse, height: usedHeight + 4),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                )
                state.y += usedHeight

                if consumed.length == remaining.length {
                    remaining = NSAttributedString()
                } else {
                    let rest = (remaining.string as NSString).substring(from: consumed.length)
                    let trimmed = rest.drop { $0 == " " || $0 == "\n" }
                    remaining = NSAttributedString(string: String(trimmed), attributes: bodyAttrs)
                    if remaining.length > 0 {
                        state.beginPage()
                    }
                }
            }
            state.y += 8
        }
        state.y += 4
    }

    // MARK: - Signature section

    private static func drawSignatureSection(
        state: inout RenderState,
        signaturesBySignerId: [String: UIImage]
    ) {
        drawSectionHeading("Signatures", state: &state)

        let contentWidth = pageWidth - margin * 2
        let signers = state.agreement.participants
        let columnGap: CGFloat = 22
        let columns: CGFloat = signers.count >= 2 ? 2 : 1
        let columnWidth = (contentWidth - columnGap * (columns - 1)) / columns
        let blockHeight: CGFloat = 150

        var col = 0
        var rowY = state.y

        for signer in signers {
            if rowY + blockHeight > contentBottom {
                state.y = rowY
                state.beginPage()
                rowY = state.y
                col = 0
            }
            let xOffset = margin + CGFloat(col) * (columnWidth + columnGap)
            drawSignatureBlock(
                signer: signer,
                image: signaturesBySignerId[signer.signerId],
                origin: CGPoint(x: xOffset, y: rowY),
                width: columnWidth,
                height: blockHeight
            )
            col += 1
            if CGFloat(col) >= columns {
                col = 0
                rowY += blockHeight + 16
            }
        }
        if col != 0 {
            rowY += blockHeight + 16
        }
        state.y = rowY + 4

        drawClosingNote(state: &state)
    }

    private static func drawSignatureBlock(
        signer: AgreementSignerSnapshot,
        image: UIImage?,
        origin: CGPoint,
        width: CGFloat,
        height: CGFloat
    ) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }

        let card = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        let path = UIBezierPath(roundedRect: card, cornerRadius: 8)
        cg.saveGState()
        cg.setFillColor(cardFill.cgColor)
        cg.addPath(path.cgPath)
        cg.fillPath()
        cg.setStrokeColor(cardStroke.cgColor)
        cg.setLineWidth(1)
        cg.addPath(path.cgPath)
        cg.strokePath()
        cg.restoreGState()

        let pad: CGFloat = 14
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: inkMuted,
            .kern: 0.4
        ]
        let role = signer.signerRole == .seeker ? "SEEKER" : "INVESTOR"
        (role as NSString).draw(
            at: CGPoint(x: card.minX + pad, y: card.minY + pad),
            withAttributes: labelAttrs
        )

        let signatureArea = CGRect(
            x: card.minX + pad,
            y: card.minY + pad + 16,
            width: card.width - pad * 2,
            height: 64
        )

        if let image {
            drawSignatureAspectFit(image: image, in: signatureArea)
        } else {
            let placeholder = "Pending signature"
            let placeholderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 11),
                .foregroundColor: inkMuted
            ]
            let size = (placeholder as NSString).size(withAttributes: placeholderAttrs)
            (placeholder as NSString).draw(
                at: CGPoint(
                    x: signatureArea.midX - size.width / 2,
                    y: signatureArea.midY - size.height / 2
                ),
                withAttributes: placeholderAttrs
            )
        }

        let lineY = signatureArea.maxY + 6
        cg.setStrokeColor(signatureLine.cgColor)
        cg.setLineWidth(0.8)
        cg.move(to: CGPoint(x: card.minX + pad, y: lineY))
        cg.addLine(to: CGPoint(x: card.maxX - pad, y: lineY))
        cg.strokePath()

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: inkPrimary
        ]
        (signer.displayName as NSString).draw(
            at: CGPoint(x: card.minX + pad, y: lineY + 6),
            withAttributes: nameAttrs
        )

        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: inkSecondary
        ]
        let metaText: String = {
            if let signed = signer.signedAt {
                return "Signed \(mediumDate(signed))"
            }
            return "Awaiting signature"
        }()
        (metaText as NSString).draw(
            at: CGPoint(x: card.minX + pad, y: lineY + 22),
            withAttributes: metaAttrs
        )
    }

    /// Aspect-fit + center; never stretch the signature.
    private static func drawSignatureAspectFit(image: UIImage, in rect: CGRect) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }
        let scale = min(rect.width / imgSize.width, rect.height / imgSize.height)
        let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }

    private static func drawClosingNote(state: inout RenderState) {
        state.ensureSpace(60)
        let note = """
        In witness whereof, the parties identified above have affixed their digital signatures \
        through Investtrust and accept the terms of this Agreement as of the dates set out against \
        each signature. Identifiers below allow each party to cross-reference this document with \
        their records.
        """
        drawParagraph(note, state: &state)
    }

    // MARK: - Content builders

    private static func partiesRows(_ a: InvestmentAgreementSnapshot) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Investor", a.investorName),
            ("Seeker", a.seekerName),
            ("Opportunity", a.opportunityTitle),
            ("Deal Structure", a.investmentType.displayName)
        ]
        if let seeker = a.participants.first(where: { $0.signerRole == .seeker }) {
            rows.append(("Seeker Reference ID", seeker.signerId))
        }
        if let investor = a.participants.first(where: { $0.signerRole == .investor }) {
            rows.append(("Investor Reference ID", investor.signerId))
        }
        return rows
    }

    private static func referenceRows(_ a: InvestmentAgreementSnapshot) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Agreement ID", a.agreementId),
            ("Schema Version", "v\(a.agreementVersion)"),
            ("Prepared On", longDate(a.createdAt)),
            ("Terms Hash", a.termsSnapshotHash)
        ]
        if !a.linkedInvestmentIds.isEmpty {
            rows.append(("Linked Investment IDs", a.linkedInvestmentIds.joined(separator: ", ")))
        }
        return rows
    }

    private static func investmentSummaryRows(_ a: InvestmentAgreementSnapshot) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Investment Amount", "LKR " + formatAmount(a.investmentAmount))
        ]
        switch a.investmentType {
        case .loan:
            if let rate = a.termsSnapshot.interestRate {
                rows.append(("Interest Rate", String(format: "%.2f%% per annum", rate)))
            }
            if let months = a.termsSnapshot.repaymentTimelineMonths {
                rows.append(("Loan Tenor", "\(months) months"))
            }
            rows.append(("Repayment Cadence", a.termsSnapshot.repaymentFrequency?.displayName ?? "Monthly"))
            if let totals = projectedLoanTotals(a) {
                rows.append(("Projected Interest Portion", "LKR " + formatAmount(totals.interest)))
                rows.append(("Projected Total Repayment", "LKR " + formatAmount(totals.total)))
            }
        case .equity:
            if let pct = a.termsSnapshot.equityPercentage {
                rows.append(("Equity Stake", String(format: "%.2f%%", pct)))
            }
            if let val = a.termsSnapshot.businessValuation, val > 0 {
                rows.append(("Business Valuation", "LKR " + formatAmount(val)))
            }
            if let months = a.termsSnapshot.equityTimelineMonths, months > 0 {
                rows.append(("Investment Horizon", "\(months) months"))
            }
            if let roi = a.termsSnapshot.equityRoiTimeline {
                rows.append(("Target ROI Timeline", roi.displayName))
            }
        }
        return rows
    }

    private static func loanTermsRows(_ a: InvestmentAgreementSnapshot) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Principal", "LKR " + formatAmount(a.investmentAmount)))
        if let rate = a.termsSnapshot.interestRate {
            rows.append(("Annual Interest Rate", String(format: "%.2f%%", rate)))
        }
        if let months = a.termsSnapshot.repaymentTimelineMonths {
            rows.append(("Tenor", "\(months) months"))
        }
        rows.append(("Frequency", a.termsSnapshot.repaymentFrequency?.displayName ?? "Monthly"))
        if let plan = projectedLoanTotals(a) {
            rows.append(("Per-installment Estimate", "LKR " + formatAmount(plan.perInstallment)))
            rows.append(("Number of Installments", "\(plan.installmentCount)"))
            rows.append(("Total Interest", "LKR " + formatAmount(plan.interest)))
            rows.append(("Total Repayment", "LKR " + formatAmount(plan.total)))
        }
        return rows
    }

    private static func equityTermsRows(_ a: InvestmentAgreementSnapshot) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Investment Amount", "LKR " + formatAmount(a.investmentAmount)))
        if let pct = a.termsSnapshot.equityPercentage {
            rows.append(("Equity Granted", String(format: "%.2f%%", pct)))
        }
        if let val = a.termsSnapshot.businessValuation, val > 0 {
            rows.append(("Pre-money Valuation", "LKR " + formatAmount(val)))
        }
        if let months = a.termsSnapshot.equityTimelineMonths, months > 0 {
            rows.append(("Investment Horizon", "\(months) months"))
        }
        if let roi = a.termsSnapshot.equityRoiTimeline {
            rows.append(("Target ROI Timeline", roi.displayName))
        }
        if let exit = a.termsSnapshot.exitPlan, !exit.isEmpty {
            rows.append(("Exit Plan", exit))
        }
        return rows
    }

    private static func ventureProfileText(_ a: InvestmentAgreementSnapshot) -> String? {
        let t = a.termsSnapshot
        var lines: [String] = []
        if let name = t.ventureName, !name.isEmpty {
            lines.append("Venture name: \(name)")
        }
        if let stage = t.ventureStage {
            lines.append("Stage: \(stage.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
        }
        if let model = t.revenueModel, !model.isEmpty {
            lines.append("Revenue model: \(model)")
        }
        if let audience = t.targetAudience, !audience.isEmpty {
            lines.append("Target audience: \(audience)")
        }
        if let goals = t.futureGoals, !goals.isEmpty {
            lines.append("Future goals: \(goals)")
        }
        if let demos = t.demoLinks, !demos.isEmpty {
            lines.append("Demo references: \(demos)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func loanRepaymentScheduleText(_ a: InvestmentAgreementSnapshot) -> String? {
        guard let plan = projectedLoanTotals(a) else { return nil }
        let freq = a.termsSnapshot.repaymentFrequency?.displayName ?? "Monthly"
        return """
        The Seeker shall repay the Principal together with Interest in \(plan.installmentCount) \
        \(freq.lowercased()) installments. Each installment is estimated at LKR \(formatAmount(plan.perInstallment)) \
        based on simple-interest amortisation over the agreed Tenor. Final installment amounts will be \
        produced inside the Investtrust app once the principal has been disbursed and may vary slightly \
        due to rounding.
        """
    }

    private static func loanCommitmentsHeading(_ a: InvestmentAgreementSnapshot) -> String {
        _ = a
        return "6.  Commitments"
    }

    private static func loanCommitments(_ a: InvestmentAgreementSnapshot) -> [String] {
        let rate = a.termsSnapshot.interestRate.map { String(format: "%.2f%%", $0) } ?? "the agreed rate"
        let months = a.termsSnapshot.repaymentTimelineMonths.map(String.init) ?? "the agreed number of"
        let freq = (a.termsSnapshot.repaymentFrequency?.displayName ?? "Monthly").lowercased()
        return [
            "The Investor agrees to transfer the Principal of LKR \(formatAmount(a.investmentAmount)) to the Seeker and to upload verifiable proof of the transfer through the Investtrust app prior to the activation of the repayment schedule.",
            "The Seeker agrees to repay the Principal together with interest at \(rate) per annum on a \(freq) basis over a tenor of \(months) months from the date the Investor records the disbursement as received.",
            "Each scheduled payment is due on its scheduled due date. Late payments may incur reminders in-app, and after any grace period an installment may be marked as defaulted at the Investor's discretion.",
            "Any changes to the Principal, interest rate, frequency, or tenor require the mutual written confirmation of both parties through the Investtrust agreement workflow; ad-hoc verbal modifications are not binding.",
            "Either party may use the in-app chat thread to coordinate disbursement, repayment receipts, and supporting evidence; communications stored there are part of the dealing record.",
            "On full repayment the Investor shall mark the loan as closed in-app, which will lock further automated reminders and finalise the in-app transaction record."
        ]
    }

    private static func equityCommitmentsHeading(_ a: InvestmentAgreementSnapshot) -> String {
        _ = a
        return "6.  Commitments"
    }

    private static func equityCommitments(_ a: InvestmentAgreementSnapshot) -> [String] {
        let pct = a.termsSnapshot.equityPercentage.map { String(format: "%.2f%%", $0) } ?? "the agreed equity stake"
        let horizon = a.termsSnapshot.equityTimelineMonths.map { "\($0) months" } ?? "the agreed horizon"
        return [
            "The Investor shall fund the agreed Investment Amount of LKR \(formatAmount(a.investmentAmount)) and submit verifiable proof of transfer through the Investtrust app.",
            "In exchange, the Seeker grants the Investor an equity interest equal to \(pct) of the venture, on the basis of the valuation recorded in this Agreement, vesting upon confirmation of the funds.",
            "The Seeker shall provide periodic venture updates (financial, operational, and milestone status) through the Investtrust venture-updates feature for the duration of the \(horizon) horizon.",
            "Both parties acknowledge the Exit Plan recorded above. Material deviations from the Exit Plan, including secondary sale of the equity granted hereunder, require written acknowledgement of both parties.",
            "Any decision that materially changes the ownership ledger, capital structure, or the agreed equity stake must be documented as a new agreement workflow inside the Investtrust app.",
            "The parties shall use the in-app chat to maintain governance discussions and shall keep the venture updates current; the platform record is the canonical record of the dealing between the parties."
        ]
    }

    private static func generalProvisions() -> [String] {
        [
            "This Agreement reflects the entirety of the parties' understanding with respect to the subject matter described above. It supersedes any prior negotiations or proposals exchanged on or off the Investtrust platform.",
            "Investtrust acts as a facilitator and record-keeper. It is not a party to the dealing and does not guarantee performance of any obligation set out in this Agreement.",
            "If any clause of this Agreement is found unenforceable, the remaining clauses shall continue in effect to the maximum extent permissible.",
            "Notices required under this Agreement shall be delivered through the in-app chat thread associated with this opportunity and shall be deemed received when read on the platform.",
            "This Agreement shall be governed by the laws of the jurisdiction in which the Seeker is ordinarily resident, unless the parties expressly agree otherwise."
        ]
    }

    // MARK: - Loan math

    private struct LoanProjection {
        let installmentCount: Int
        let perInstallment: Double
        let interest: Double
        let total: Double
    }

    private static func projectedLoanTotals(_ a: InvestmentAgreementSnapshot) -> LoanProjection? {
        guard a.investmentType == .loan else { return nil }
        let principal = a.investmentAmount
        guard principal > 0 else { return nil }
        let rate = a.termsSnapshot.interestRate ?? 0
        let months = a.termsSnapshot.repaymentTimelineMonths ?? 0
        guard months > 0 else { return nil }

        let installmentCount: Int = {
            switch a.termsSnapshot.repaymentFrequency ?? .monthly {
            case .monthly: return months
            case .weekly: return max(1, Int((Double(months) * 4.345).rounded()))
            case .one_time: return 1
            }
        }()

        let interest = principal * (rate / 100.0) * (Double(months) / 12.0)
        let total = principal + interest
        let per = total / Double(installmentCount)
        return LoanProjection(installmentCount: installmentCount, perInstallment: per, interest: interest, total: total)
    }

    // MARK: - Helpers

    private static func breakAttributedString(
        _ source: NSAttributedString,
        width: CGFloat,
        maxHeight: CGFloat
    ) -> (NSAttributedString, CGFloat) {
        guard maxHeight > 12 else { return (NSAttributedString(), 0) }
        let framesetter = CTFramesetterCreateWithAttributedString(source as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: maxHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, source.length), path, nil)
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        guard visibleRange.length > 0 else { return (NSAttributedString(), 0) }
        let consumed = source.attributedSubstring(from: NSRange(location: visibleRange.location, length: visibleRange.length))
        let usedHeight = consumed.boundingRect(
            with: CGSize(width: width, height: 4000),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).height
        return (consumed, usedHeight)
    }

    private static func drawAttributedFlowing(_ source: NSAttributedString, width: CGFloat, state: inout RenderState) {
        var remaining = source
        while remaining.length > 0 {
            let available = max(24, contentBottom - state.y)
            let (consumed, used) = breakAttributedString(remaining, width: width, maxHeight: available)
            if consumed.length == 0 {
                state.beginPage()
                continue
            }
            consumed.draw(
                with: CGRect(x: margin, y: state.y, width: width, height: used + 4),
                options: [.usesLineFragmentOrigin],
                context: nil
            )
            state.y += used
            if consumed.length == remaining.length {
                break
            }
            let rest = (remaining.string as NSString).substring(from: consumed.length)
            let trimmed = rest.drop { $0 == " " || $0 == "\n" }
            let attrs = remaining.attributes(at: 0, effectiveRange: nil)
            remaining = NSAttributedString(string: String(trimmed), attributes: attrs)
            if remaining.length > 0 {
                state.beginPage()
            }
        }
    }

    private static func shortHash(_ full: String) -> String {
        if full.count <= 14 { return full }
        return String(full.prefix(8)) + "…" + String(full.suffix(6))
    }

    private static func formatAmount(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: n) ?? String(format: "%.0f", v)
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private static func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: d)
    }
}
