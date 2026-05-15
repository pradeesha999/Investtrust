import Foundation

// Parses the Cloudinary public_id out of a delivery URL for older listings that didn't store it separately
enum CloudinaryPublicIdExtractor {
    enum ResourceFolder: String {
        case image
        case video
    }

    // Extracts the public_id path segment (e.g. "folder/file") from a Cloudinary HTTPS URL
    static func publicId(fromDeliveryURL string: String) -> String? {
        guard let url = URL(string: string),
              let host = url.host?.lowercased(),
              host == "res.cloudinary.com" || host.hasSuffix(".res.cloudinary.com")
        else { return nil }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let uploadIdx = parts.firstIndex(of: "upload") else { return nil }
        var i = uploadIdx + 1
        while i < parts.count {
            let seg = parts[i]
            if seg.hasPrefix("v"), seg.dropFirst().allSatisfy(\.isNumber) {
                i += 1
                continue
            }
            break
        }
        guard i < parts.count else { return nil }
        let rest = parts[i...].joined(separator: "/")
        let decoded = rest.removingPercentEncoding ?? rest
        let withoutExt = (decoded as NSString).deletingPathExtension
        return withoutExt.isEmpty ? nil : withoutExt
    }

    static func resourceFolder(fromDeliveryURL string: String) -> ResourceFolder? {
        let path = (URL(string: string)?.path ?? "").lowercased()
        if path.contains("/video/") { return .video }
        if path.contains("/image/") { return .image }
        return .image
    }
}
