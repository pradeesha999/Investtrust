import CryptoKit
import Foundation

// Downloads remote media files (images, videos) once per session and caches them on disk.
// Prevents repeated network fetches when the user scrolls through deal media.
actor SessionMediaCache {
    static let shared = SessionMediaCache()

    private let memoryFileURL = NSCache<NSString, NSURL>()
    private var inFlight: [String: Task<URL, Error>] = [:]

    private var directoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("InvesttrustSessionMedia", isDirectory: true)
    }

    // Returns a local file:// URL for the given remote URL — downloads the file on first access
    func materializeRemoteFile(at remote: URL) async throws -> URL {
        if remote.isFileURL { return remote }

        guard let scheme = remote.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return remote
        }

        let key = remote.absoluteString
        if let hit = memoryFileURL.object(forKey: key as NSString) {
            return hit as URL
        }

        let dest = fileURL(forKey: key)
        if FileManager.default.fileExists(atPath: dest.path) {
            memoryFileURL.setObject(dest as NSURL, forKey: key as NSString)
            return dest
        }

        if let task = inFlight[key] {
            let url = try await task.value
            return url
        }

        let task = Task<URL, Error> {
            try await self.download(remote: remote, to: dest, cacheKey: key)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let url = try await task.value
        return url
    }

    func clear() {
        memoryFileURL.removeAllObjects()
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: directoryURL)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func download(remote: URL, to dest: URL, cacheKey: String) async throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let (tmp, response) = try await URLSession.shared.download(from: remote)
        defer { try? FileManager.default.removeItem(at: tmp) }

        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw NSError(
                domain: "Investtrust",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."]
            )
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: tmp, to: dest)

        memoryFileURL.setObject(dest as NSURL, forKey: cacheKey as NSString)
        return dest
    }

    private func fileURL(forKey key: String) -> URL {
        let name = Self.sha256Hex(key) + "." + Self.preferredExtension(forRemoteKey: key)
        return directoryURL.appendingPathComponent(name)
    }

    private static func preferredExtension(forRemoteKey key: String) -> String {
        if let url = URL(string: key) {
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty, ext.count <= 5 {
                return ext
            }
        }
        return "bin"
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    // Posted when the user signs out so UI layers can clear their own image/video caches
    static let investtrustSessionMediaDidReset = Notification.Name("investtrustSessionMediaDidReset")
}
