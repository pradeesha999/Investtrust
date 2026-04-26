import CryptoKit
import PDFKit
import UIKit

/// Renders a styled multi-page MOA PDF (Core Graphics). Display in-app with `PDFDocument(data:)` / `PDFView`.
enum MOAPDFBuilder {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let pageWidth = pageRect.width
    private static let pageHeight = pageRect.height

    /// Brand-aligned header (deep slate). Body uses neutral grays.
    private static let headerFill = UIColor(red: 0.11, green: 0.18, blue: 0.28, alpha: 1)
    private static let cardFill = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
    private static let cardStroke = UIColor(red: 0.88, green: 0.91, blue: 0.94, alpha: 1)
    private static let accentLine = UIColor(red: 0.78, green: 0.22, blue: 0.35, alpha: 1)

    static func buildPDF(
        agreement: InvestmentAgreementSnapshot,
        signaturesBySignerId: [String: UIImage]
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { pdfCtx in
            pdfCtx.beginPage()
            guard let cg = UIGraphicsGetCurrentContext() else { return }

            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(pageRect)

            drawPageHeader(in: cg, agreement: agreement)

            var y: CGFloat = 118
            let margin: CGFloat = 44
            let contentWidth = pageWidth - margin * 2
            let corner: CGFloat = 8

            y = drawSectionCard(
                cg: cg,
                y: y,
                margin: margin,
                width: contentWidth,
                corner: corner,
                title: "PARTIES & ECONOMICS",
                body: partiesBlock(agreement)
            )

            y = drawSectionCard(
                cg: cg,
                y: y,
                margin: margin,
                width: contentWidth,
                corner: corner,
                title: "TERMS SNAPSHOT",
                body: termsSummary(for: agreement)
            )

            y = drawSectionCard(
                cg: cg,
                y: y,
                margin: margin,
                width: contentWidth,
                corner: corner,
                title: "COMMITMENTS",
                body: rulesSummary(for: agreement)
            )

            let footer = "Agreement ID \(agreement.agreementId)  •  Version \(agreement.agreementVersion)  •  Terms hash \(shortHash(agreement.termsSnapshotHash))"
            drawFlowingFooter(footer, y: &y, margin: margin, width: contentWidth)
            y += 8
            drawSignaturesHeading(at: &y, margin: margin, width: contentWidth)

            layoutSignatures(
                pdfCtx: pdfCtx,
                cg: cg,
                startY: y,
                margin: margin,
                contentWidth: contentWidth,
                agreement: agreement,
                signaturesBySignerId: signaturesBySignerId
            )
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

    // MARK: - Layout

    private static func drawPageHeader(in cg: CGContext, agreement: InvestmentAgreementSnapshot) {
        let headerH: CGFloat = 92
        let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: headerH)
        cg.setFillColor(headerFill.cgColor)
        cg.fill(headerRect)

        let title = "Memorandum of Agreement"
        let subtitle = "\(agreement.opportunityTitle)  •  Prepared \(mediumDate(agreement.createdAt))"

        let tFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let sFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        (title as NSString).draw(
            at: CGPoint(x: 44, y: 26),
            withAttributes: [
                .font: tFont,
                .foregroundColor: UIColor.white
            ]
        )
        (subtitle as NSString).draw(
            at: CGPoint(x: 44, y: 56),
            withAttributes: [
                .font: sFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.88)
            ]
        )
    }

    private static func drawMinimalHeader(in cg: CGContext, title: String) {
        let headerH: CGFloat = 52
        cg.setFillColor(headerFill.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: pageWidth, height: headerH))
        (title as NSString).draw(
            at: CGPoint(x: 44, y: 16),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        )
    }

    private static func partiesBlock(_ agreement: InvestmentAgreementSnapshot) -> String {
        """
        Opportunity: \(agreement.opportunityTitle)
        Investor: \(agreement.investorName)
        Seeker: \(agreement.seekerName)
        Investment (LKR): \(formatAmount(agreement.investmentAmount))
        Structure: \(agreement.investmentType.displayName)

        Funding and repayments occur outside this platform unless the parties agree otherwise in writing.
        """
    }

    private static func drawSectionCard(
        cg: CGContext,
        y: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        corner: CGFloat,
        title: String,
        body: String
    ) -> CGFloat {
        let titleFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.lineBreakMode = .byWordWrapping

        let titleAttr = NSAttributedString(
            string: title,
            attributes: [
                .font: titleFont,
                .foregroundColor: UIColor.darkGray
            ]
        )
        let bodyAttr = NSAttributedString(
            string: body,
            attributes: [
                .font: bodyFont,
                .foregroundColor: UIColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1),
                .paragraphStyle: para
            ]
        )

        let titleH = titleAttr.boundingRect(
            with: CGSize(width: width - 28, height: 2000),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).height
        let bodyH = bodyAttr.boundingRect(
            with: CGSize(width: width - 28, height: 2000),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).height

        let pad: CGFloat = 14
        let accentW: CGFloat = 4
        let cardH = pad + titleH + 8 + bodyH + pad
        let cardRect = CGRect(x: margin, y: y, width: width, height: cardH)

        cg.saveGState()
        cg.setFillColor(cardFill.cgColor)
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: corner)
        cg.addPath(path.cgPath)
        cg.fillPath()
        cg.setStrokeColor(cardStroke.cgColor)
        cg.setLineWidth(1)
        cg.addPath(path.cgPath)
        cg.strokePath()

        cg.setFillColor(accentLine.cgColor)
        cg.fill(CGRect(x: margin, y: y + pad, width: accentW, height: max(24, titleH + bodyH + 8)))

        let innerX = margin + pad + accentW + 10
        titleAttr.draw(in: CGRect(x: innerX, y: y + pad, width: width - 28 - accentW, height: titleH + 4))
        bodyAttr.draw(in: CGRect(x: innerX, y: y + pad + titleH + 8, width: width - 28 - accentW, height: bodyH + 8))
        cg.restoreGState()

        return y + cardH + 14
    }

    private static func drawFlowingFooter(_ text: String, y: inout CGFloat, margin: CGFloat, width: CGFloat) {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.gray
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let h = s.boundingRect(
            with: CGSize(width: width, height: 2000),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).height
        s.draw(in: CGRect(x: margin, y: y, width: width, height: h + 4))
        y += h + 12
    }

    private static func drawSignaturesHeading(at y: inout CGFloat, margin: CGFloat, width: CGFloat) {
        let font = UIFont.systemFont(ofSize: 13, weight: .bold)
        ("SIGNATURES" as NSString).draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: [.font: font, .foregroundColor: headerFill]
        )
        y += 22
    }

    private static func layoutSignatures(
        pdfCtx: UIGraphicsPDFRendererContext,
        cg: CGContext,
        startY: CGFloat,
        margin: CGFloat,
        contentWidth: CGFloat,
        agreement: InvestmentAgreementSnapshot,
        signaturesBySignerId: [String: UIImage]
    ) {
        var sigTop = startY
        let sigW = contentWidth
        let sigH: CGFloat = 56
        let labelFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let metaFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        for signer in agreement.participants {
            if sigTop + sigH + 48 > pageHeight - 48 {
                pdfCtx.beginPage()
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(pageRect)
                drawMinimalHeader(in: cg, title: "Signatures (continued)")
                sigTop = 72
            }

            let roleLabel = signer.signerRole == .seeker ? "Seeker" : "Investor"
            ("\(signer.displayName) — \(roleLabel)" as NSString).draw(
                at: CGPoint(x: margin, y: sigTop),
                withAttributes: [.font: labelFont]
            )
            let signedAtLabel = signer.signedAt.map { "Signed \(mediumDate($0))" } ?? "Pending signature"
            (signedAtLabel as NSString).draw(
                at: CGPoint(x: margin + min(280, contentWidth * 0.45), y: sigTop),
                withAttributes: [.font: metaFont, .foregroundColor: UIColor.darkGray]
            )

            let boxY = sigTop + 18
            let boxRect = CGRect(x: margin, y: boxY, width: sigW, height: sigH)
            cg.setFillColor(cardFill.cgColor)
            cg.setStrokeColor(cardStroke.cgColor)
            let boxPath = UIBezierPath(roundedRect: boxRect.insetBy(dx: 0, dy: 0), cornerRadius: 6)
            cg.addPath(boxPath.cgPath)
            cg.fillPath()
            cg.setLineWidth(1)
            cg.addPath(boxPath.cgPath)
            cg.strokePath()

            if let img = signaturesBySignerId[signer.signerId]?.normalizedForPDF(maxWidth: sigW - 16, maxHeight: sigH - 8) {
                img.draw(in: boxRect.insetBy(dx: 8, dy: 4))
            } else {
                drawPlaceholder(in: boxRect.insetBy(dx: 8, dy: 4))
            }
            sigTop += sigH + 32
        }
    }

    private static func drawPlaceholder(in rect: CGRect) {
        let font = UIFont.italicSystemFont(ofSize: 10)
        ("Awaiting signature" as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: UIColor.lightGray
            ]
        )
    }

    private static func shortHash(_ full: String) -> String {
        if full.count <= 14 { return full }
        return String(full.prefix(8)) + "…" + String(full.suffix(6))
    }

    private static func formatAmount(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
    }

    private static func mediumDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    private static func termsSummary(for agreement: InvestmentAgreementSnapshot) -> String {
        let t = agreement.termsSnapshot
        switch agreement.investmentType {
        case .loan:
            let rate = t.interestRate.map { String(format: "%.2f%%", $0) } ?? "—"
            let mo = t.repaymentTimelineMonths.map { "\($0) months" } ?? "—"
            let freq = t.repaymentFrequency?.displayName ?? "Monthly"
            return "Interest: \(rate)\nRepayment timeline: \(mo)\nFrequency: \(freq)"
        case .equity:
            var lines: [String] = []
            if let p = t.equityPercentage { lines.append("Equity: \(String(format: "%.1f%%", p))") }
            if let e = t.exitPlan, !e.isEmpty { lines.append("Exit: \(e)") }
            return lines.isEmpty ? "—" : lines.joined(separator: "\n")
        case .revenue_share:
            var lines: [String] = []
            if let p = t.revenueSharePercent { lines.append("Revenue share: \(String(format: "%.1f%%", p))") }
            if let a = t.targetReturnAmount { lines.append("Target return (LKR): \(formatAmount(a))") }
            return lines.isEmpty ? "—" : lines.joined(separator: "\n")
        case .project:
            return [
                t.expectedReturnType.map { "Return type: \($0.rawValue)" },
                t.expectedReturnValue.map { "Expected return: \($0)" },
                t.completionDate.map { "Completion: \(mediumDate($0))" }
            ].compactMap(\.self).joined(separator: "\n")
        case .custom:
            return t.customTermsSummary ?? "—"
        }
    }

    private static func rulesSummary(for agreement: InvestmentAgreementSnapshot) -> String {
        let t = agreement.termsSnapshot
        let freq = t.repaymentFrequency?.displayName ?? "Monthly"
        let months = t.repaymentTimelineMonths.map(String.init) ?? "—"
        let rate = t.interestRate.map { String(format: "%.2f%%", $0) } ?? "—"
        return """
        1. The seeker agrees to repay principal and interest according to the agreed cadence (\(freq)) over \(months) months.
        2. Payments are due on each scheduled due date; missed payments may shift status to defaulted after any grace period.
        3. Changes to amount, rate (\(rate)), or timeline require mutual confirmation between the parties.
        4. This PDF is generated from the in-app memorandum and signature record for the parties’ files.
        """
    }
}

private extension UIImage {
    func normalizedForPDF(maxWidth: CGFloat, maxHeight: CGFloat) -> UIImage? {
        let r = self
        let scale = min(maxWidth / max(r.size.width, 1), maxHeight / max(r.size.height, 1), 1)
        let newSize = CGSize(width: r.size.width * scale, height: r.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        defer { UIGraphicsEndImageContext() }
        r.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
