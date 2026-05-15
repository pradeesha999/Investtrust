import FirebaseStorage
import SwiftUI
import UIKit

// Loads and caches images from Firebase Storage paths or HTTPS URLs for use in opportunity cards and carousels
struct StorageBackedAsyncImage: View {
    let reference: String?
    var height: CGFloat = 220
    var cornerRadius: CGFloat = 16
    // When `true`, Cloudinary `res.cloudinary.com/.../image/upload/...` URLs get a width-limited transform so feed rows don’t download full-size originals.
    var feedThumbnail: Bool = false

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    private var effectiveReference: String? {
        guard let reference, !reference.isEmpty else { return nil }
        guard feedThumbnail else { return reference }
        return Self.cloudinaryFeedOptimizedURL(reference)
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                placeholder(icon: "photo")
                    .overlay(ProgressView())
            } else {
                placeholder(icon: "photo")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: effectiveReference) {
            await loadImage()
        }
    }

    private static func cloudinaryFeedOptimizedURL(_ ref: String) -> String {
        let t = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.contains("res.cloudinary.com"), t.contains("/image/upload/") else { return t }
        if t.contains("/image/upload/w_") || t.contains("/image/upload/c_") || t.contains("/image/upload/h_") {
            return t
        }
        return t.replacingOccurrences(
            of: "/image/upload/",
            with: "/image/upload/w_720,c_limit,q_auto,f_auto/"
        )
    }

    private func placeholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            )
    }

    private func loadImage() async {
        guard let reference = effectiveReference, !reference.isEmpty else {
            await MainActor.run { uiImage = nil }
            return
        }

        if let cached = CachedImageLoader.cachedImage(for: reference) {
            await MainActor.run {
                uiImage = cached
                isLoading = false
            }
            return
        }

        await MainActor.run { isLoading = true }
        let image = await CachedImageLoader.loadImage(reference: reference)
        await MainActor.run {
            uiImage = image
            isLoading = false
        }
    }
}
