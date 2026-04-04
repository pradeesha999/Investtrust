import FirebaseStorage
import UIKit

/// In-memory cache so carousel pages / TabView don’t re-download when swiping back.
enum CachedImageLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 150
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

    private static func key(for reference: String) -> String {
        reference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cachedImage(for reference: String) -> UIImage? {
        let k = key(for: reference)
        guard !k.isEmpty else { return nil }
        return cache.object(forKey: k as NSString)
    }

    /// Loads from cache or network; stores in cache on success.
    static func loadImage(reference: String) async -> UIImage? {
        let k = key(for: reference)
        guard !k.isEmpty else { return nil }
        if let hit = cache.object(forKey: k as NSString) {
            return hit
        }
        guard let image = await loadFromNetwork(reference: k) else { return nil }
        let cost = image.jpegData(compressionQuality: 1)?.count ?? 256_000
        cache.setObject(image, forKey: k as NSString, cost: cost)
        return image
    }

    /// Warm cache for all carousel URLs before auto-advance switches pages.
    /// Clears in-memory images (e.g. on sign-out). Disk session cache is cleared separately.
    static func clearMemoryCache() {
        cache.removeAllObjects()
    }

    static func preload(references: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for ref in references {
                let trimmed = key(for: ref)
                guard !trimmed.isEmpty else { continue }
                group.addTask {
                    _ = await loadImage(reference: trimmed)
                }
            }
        }
    }

    private static func loadFromNetwork(reference: String) async -> UIImage? {
        if reference.hasPrefix("http://") || reference.hasPrefix("https://") {
            if isFirebaseStorageHTTPS(reference) {
                let ref = Storage.storage().reference(forURL: reference)
                return await loadFromStorageReference(ref)
            }
            return await loadFromRemoteURL(reference)
        }

        if reference.hasPrefix("gs://") {
            let ref = Storage.storage().reference(forURL: reference)
            return await loadFromStorageReference(ref)
        }

        let path = reference.hasPrefix("/") ? String(reference.dropFirst()) : reference
        guard !path.isEmpty else { return nil }
        let ref = Storage.storage().reference(withPath: path)
        return await loadFromStorageReference(ref)
    }

    private static func loadFromRemoteURL(_ string: String) async -> UIImage? {
        guard let url = URL(string: string) else { return nil }
        if url.scheme == "https" || url.scheme == "http" {
            do {
                let local = try await SessionMediaCache.shared.materializeRemoteFile(at: url)
                if let image = UIImage(contentsOfFile: local.path) {
                    return image
                }
            } catch {
                // fall through to direct fetch
            }
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private static func loadFromStorageReference(_ ref: StorageReference) async -> UIImage? {
        let maxBytes: Int64 = 20 * 1024 * 1024
        do {
            let data = try await ref.data(maxSize: maxBytes)
            if let image = UIImage(data: data) { return image }
        } catch {
            // fall through
        }
        do {
            let url = try await ref.downloadURL()
            do {
                let local = try await SessionMediaCache.shared.materializeRemoteFile(at: url)
                if let image = UIImage(contentsOfFile: local.path) {
                    return image
                }
            } catch {
                // fall through
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private static func isFirebaseStorageHTTPS(_ s: String) -> Bool {
        s.lowercased().contains("firebasestorage.googleapis.com")
    }
}
