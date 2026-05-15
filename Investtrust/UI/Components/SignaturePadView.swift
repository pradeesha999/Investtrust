import SwiftUI
import UIKit

// Freehand signature drawing pad used on the MOA signing screen.
// Renders ink strokes in real time and exports a PNG when the user confirms their signature.

// Isolated helper that renders the drawn strokes to a PNG without triggering a full view rebuild
private enum SignaturePNGExporter {
    @MainActor
    static func pngData(
        strokes: [[CGPoint]],
        current: [CGPoint],
        lineWidth: CGFloat = 2.5
    ) -> Data? {
        let all = strokes + (current.count >= 2 ? [current] : [])
        guard !all.isEmpty else { return nil }
        let combined = all.flatMap { $0 }
        guard let bbox = boundingRect(points: combined, pad: 8) else { return nil }

        let exportView = SignatureInkExportView(
            strokes: strokes,
            current: current,
            lineWidth: lineWidth,
            cropRect: bbox
        )
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = UITraitCollection.current.displayScale
        return renderer.uiImage?.pngData()
    }

    private static func boundingRect(points: [CGPoint], pad: CGFloat) -> CGRect? {
        guard let first = points.first else { return nil }
        var r = CGRect(origin: first, size: .zero)
        for p in points.dropFirst() {
            r = r.union(CGRect(origin: p, size: .zero))
        }
        guard r.width.isFinite, r.height.isFinite else { return nil }
        return r.insetBy(dx: -pad, dy: -pad)
    }
}

private struct SignatureInkExportView: View {
    let strokes: [[CGPoint]]
    let current: [CGPoint]
    let lineWidth: CGFloat
    let cropRect: CGRect

    var body: some View {
        Canvas { ctx, _ in
            let all = strokes + (current.count >= 2 ? [current] : [])
            let ox = cropRect.minX
            let oy = cropRect.minY
            for stroke in all where stroke.count >= 2 {
                var path = Path()
                path.move(to: CGPoint(x: stroke[0].x - ox, y: stroke[0].y - oy))
                for i in 1 ..< stroke.count {
                    path.addLine(to: CGPoint(x: stroke[i].x - ox, y: stroke[i].y - oy))
                }
                ctx.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: max(cropRect.width, 1), height: max(cropRect.height, 1))
        .background(Color.clear)
    }
}

// Interactive pad + actions (local @State only — parent terms view does not re-render per touch)

// Signature capture **outside** a parent `ScrollView` is strongly recommended so gestures stay reliable.
struct AgreementSignaturePanel: View {
    var accentColor: Color
    // Disable Sign when agreement snapshot is missing.
    var agreementMissing: Bool
    @Binding var isSigning: Bool
    @Binding var errorText: String?
    // Called with PNG bytes after user taps Sign & submit.
    var onSign: (Data) async throws -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []

    private let padHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let err = errorText, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Sign below")
                .font(.headline)
            Text("Your signature is embedded in the official PDF memorandum.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Canvas { context, _ in
                func drawStroke(_ pts: [CGPoint]) {
                    guard pts.count >= 2 else { return }
                    var path = Path()
                    path.move(to: pts[0])
                    for i in 1 ..< pts.count {
                        path.addLine(to: pts[i])
                    }
                    context.stroke(
                        path,
                        with: .color(Color.primary),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }
                for s in strokes { drawStroke(s) }
                drawStroke(current)
            }
            .frame(height: padHeight)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        current = current + [value.location]
                    }
                    .onEnded { _ in
                        if current.count >= 2 {
                            strokes = strokes + [current]
                        } else if current.count == 1 {
                            let p = current[0]
                            strokes = strokes + [[p, CGPoint(x: p.x + 1, y: p.y)]]
                        }
                        current = []
                    }
            )

            Button("Clear signature") {
                strokes = []
                current = []
            }
            .font(.subheadline)
            .disabled(isSigning)

            Button {
                Task { @MainActor in
                    await runSubmit()
                }
            } label: {
                if isSigning {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Sign & submit")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .buttonStyle(.plain)
            .background(accentColor, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .foregroundStyle(.white)
            .disabled(isSigning || agreementMissing)
        }
    }

    private func looksLikeRawStoragePath(_ s: String) -> Bool {
        s.hasPrefix("Object ") && s.contains("investments/")
    }

    @MainActor
    private func runSubmit() async {
        errorText = nil
        guard let data = SignaturePNGExporter.pngData(strokes: strokes, current: current),
              !data.isEmpty
        else {
            errorText = "Draw your signature before submitting."
            return
        }
        isSigning = true
        defer { isSigning = false }
        do {
            try await onSign(data)
        } catch {
            if let le = error as? LocalizedError, let d = le.errorDescription, !looksLikeRawStoragePath(d) {
                errorText = d
            } else {
                errorText = StorageFriendlyError.userMessage(for: error)
            }
        }
    }
}
