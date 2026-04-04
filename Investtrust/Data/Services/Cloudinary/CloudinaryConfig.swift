import Foundation

/// Unsigned upload settings (safe to ship). Override via `Investtrust-Info.plist` keys if needed.
enum CloudinaryConfig {
    private static func plistString(_ key: String, default defaultValue: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultValue : trimmed
    }

    static var cloudName: String {
        plistString("CLOUDINARY_CLOUD_NAME", default: "dic8bbkur")
    }

    static var uploadPreset: String {
        plistString("CLOUDINARY_UPLOAD_PRESET", default: "Investtrust")
    }

    /// Optional. Required only for **deleting** assets via the Admin/Upload destroy API. Prefer a backend in production — see `CloudinaryDestroyClient`.
    static var apiKey: String? {
        let s = (Bundle.main.object(forInfoDictionaryKey: "CLOUDINARY_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    /// Optional. Never ship this in a public client if you can avoid it; use a Cloud Function for deletes instead.
    static var apiSecret: String? {
        let s = (Bundle.main.object(forInfoDictionaryKey: "CLOUDINARY_API_SECRET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    static var hasSignedApiCredentials: Bool {
        apiKey != nil && apiSecret != nil
    }
}
