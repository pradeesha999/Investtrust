import PDFKit
import SwiftUI
import UIKit

/// Presents `MOAPDFViewerSheet` after async generation.
struct MOAPDFSheetItem: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}

// MARK: - PDFKit display

struct MOAPDFKitView: UIViewRepresentable {
    let document: PDFDocument?

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayDirection = .vertical
        v.displayMode = .singlePageContinuous
        v.displayBox = .mediaBox
        v.backgroundColor = UIColor.secondarySystemBackground
        return v
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}

// MARK: - Full-screen viewer + share

struct MOAPDFViewerSheet: View {
    let pdfData: Data
    let filename: String

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    private var document: PDFDocument? {
        PDFDocument(data: pdfData)
    }

    var body: some View {
        NavigationStack {
            Group {
                if document != nil {
                    MOAPDFKitView(document: document)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Couldn’t open PDF", systemImage: "doc.text")
                }
            }
            .navigationTitle("Memorandum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showShare = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showShare) {
            MOAPDFActivityView(pdfData: pdfData, filename: filename)
        }
    }
}

// MARK: - UIActivityViewController wrapper

private struct MOAPDFActivityView: UIViewControllerRepresentable {
    let pdfData: Data
    let filename: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? pdfData.write(to: url)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
            dismiss()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
