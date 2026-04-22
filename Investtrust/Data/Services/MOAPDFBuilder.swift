import CryptoKit
import UIKit

/// Renders a simple multi-page MOA PDF with optional embedded signature images.
enum MOAPDFBuilder {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func buildPDF(
        agreement: InvestmentAgreementSnapshot,
        investorSignature: UIImage?,
        seekerSignature: UIImage?
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 48
            let margin: CGFloat = 48
            let contentWidth = pageRect.width - margin * 2

            func drawHeading(_ text: String, size: CGFloat = 18) {
                let font = UIFont.systemFont(ofSize: size, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let s = NSAttributedString(string: text, attributes: attrs)
                let r = CGRect(x: margin, y: y, width: contentWidth, height: 800)
                s.draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += s.boundingRect(with: CGSize(width: contentWidth, height: 2000), options: [.usesLineFragmentOrigin], context: nil).height + 16
            }

            func drawBody(_ text: String) {
                let font = UIFont.systemFont(ofSize: 11, weight: .regular)
                let para = NSMutableParagraphStyle()
                para.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: para
                ]
                let s = NSAttributedString(string: text, attributes: attrs)
                let r = CGRect(x: margin, y: y, width: contentWidth, height: pageRect.height - y - margin)
                s.draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += s.boundingRect(with: CGSize(width: contentWidth, height: 2000), options: [.usesLineFragmentOrigin], context: nil).height + 12
            }

            drawHeading("Memorandum of Agreement")
            drawBody(
                """
                This memorandum records the understanding between the parties below regarding the investment described. \
                Funding and repayments occur outside this platform unless otherwise agreed in writing.

                Opportunity: \(agreement.opportunityTitle)
                Investor: \(agreement.investorName)
                Opportunity builder (seeker): \(agreement.seekerName)
                Investment amount (LKR): \(formatAmount(agreement.investmentAmount))
                Structure: \(agreement.investmentType.displayName)
                Prepared: \(mediumDate(agreement.createdAt))
                """
            )

            drawHeading("Terms snapshot", size: 14)
            drawBody(termsSummary(for: agreement))

            y = max(y, pageRect.height - 220)
            drawHeading("Signatures", size: 14)

            let sigW: CGFloat = 240
            let sigH: CGFloat = 80
            let colGap: CGFloat = 40
            let invX = margin
            let seekX = margin + sigW + colGap
            let sigTop = y
            let labelFont = UIFont.systemFont(ofSize: 11, weight: .semibold)

            ("Investor" as NSString).draw(at: CGPoint(x: invX, y: sigTop), withAttributes: [.font: labelFont])
            ("Opportunity builder" as NSString).draw(at: CGPoint(x: seekX, y: sigTop), withAttributes: [.font: labelFont])

            let boxY = sigTop + 20
            if let img = investorSignature?.normalizedForPDF(maxWidth: sigW, maxHeight: sigH) {
                img.draw(in: CGRect(x: invX, y: boxY, width: sigW, height: sigH))
            } else {
                drawPlaceholderBox(CGRect(x: invX, y: boxY, width: sigW, height: sigH))
            }
            if let img = seekerSignature?.normalizedForPDF(maxWidth: sigW, maxHeight: sigH) {
                img.draw(in: CGRect(x: seekX, y: boxY, width: sigW, height: sigH))
            } else {
                drawPlaceholderBox(CGRect(x: seekX, y: boxY, width: sigW, height: sigH))
            }
        }
    }

    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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

    private static func drawPlaceholderBox(_ rect: CGRect) {
        let path = UIBezierPath(rect: rect)
        UIColor.lightGray.setStroke()
        path.lineWidth = 1
        path.stroke()
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
