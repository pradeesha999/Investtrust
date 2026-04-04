import FirebaseStorage
import SwiftUI
import UIKit

/// Loads an image from a Firebase Storage path, `gs://` URL, Firebase **HTTPS** download URL, or any other `https://` URL.
/// Normalizes paths and falls back to a tokenized download URL when direct `data(maxSize:)` fails (rules / SDK quirks).
struct StorageBackedAsyncImage: View {
    let reference: String?
    var height: CGFloat = 220
    var cornerRadius: CGFloat = 16

    @State private var uiImage: UIImage?
    @State private var isLoading = false

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
        .task(id: reference) {
            await loadImage()
        }
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
        uiImage = nil
        guard let reference, !reference.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if Self.isFirebaseStorageHTTPS(trimmed) {
                let ref = Storage.storage().reference(forURL: trimmed)
                await loadFromStorageReference(ref)
            } else {
                await loadFromRemoteURL(trimmed)
            }
            return
        }

        if trimmed.hasPrefix("gs://") {
            let ref = Storage.storage().reference(forURL: trimmed)
            await loadFromStorageReference(ref)
            return
        }

        let path = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        guard !path.isEmpty else { return }
        let ref = Storage.storage().reference(withPath: path)
        await loadFromStorageReference(ref)
    }

    private func loadFromRemoteURL(_ string: String) async {
        guard let url = URL(string: string) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                uiImage = UIImage(data: data)
            }
        } catch {
            await MainActor.run { uiImage = nil }
        }
    }

    private func loadFromStorageReference(_ ref: StorageReference) async {
        let maxBytes: Int64 = 20 * 1024 * 1024
        do {
            let data = try await ref.data(maxSize: maxBytes)
            let image = UIImage(data: data)
            await MainActor.run { uiImage = image }
            if image != nil { return }
        } catch {
            // fall through to download URL
        }

        do {
            let url = try await ref.downloadURL()
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                uiImage = UIImage(data: data)
            }
        } catch {
            await MainActor.run { uiImage = nil }
        }
    }

    private static func isFirebaseStorageHTTPS(_ s: String) -> Bool {
        s.lowercased().contains("firebasestorage.googleapis.com")
    }
}
