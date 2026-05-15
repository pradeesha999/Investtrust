import Foundation

// Cloudinary account settings used for uploading opportunity images and videos.
// Values are read from the app's Info.plist so they can be overridden without recompiling.
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

    // Only needed when deleting assets — should ideally be handled server-side in production
    static var apiKey: String? {
        let s = (Bundle.main.object(forInfoDictionaryKey: "CLOUDINARY_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    // Should be moved to a server-side Cloud Function before the app goes to production
    static var apiSecret: String? {
        let s = (Bundle.main.object(forInfoDictionaryKey: "CLOUDINARY_API_SECRET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    static var hasSignedApiCredentials: Bool {
        apiKey != nil && apiSecret != nil
    }
}
