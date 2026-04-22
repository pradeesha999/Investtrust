import SwiftUI
import UIKit
import VisionKit

/// Presents `VNDocumentCameraViewController` and returns scanned page images as JPEG data.
struct DocumentCameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onScannedImages: ([Data]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraView

        init(parent: DocumentCameraView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var chunks: [Data] = []
            for i in 0..<scan.pageCount {
                let img = scan.imageOfPage(at: i)
                if let jpeg = img.jpegData(compressionQuality: 0.88) {
                    chunks.append(jpeg)
                }
            }
            parent.onScannedImages(chunks)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onScannedImages([])
            parent.dismiss()
        }
    }
}
