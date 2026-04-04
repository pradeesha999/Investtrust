import Foundation

struct OpportunityListing: Identifiable, Equatable, Hashable {
    let id: String
    let ownerId: String
    let title: String
    let category: String
    let description: String
    let amountRequested: Double
    let interestRate: Double
    let repaymentTimelineMonths: Int
    let status: String
    let createdAt: Date?
    let imageStoragePaths: [String]
    /// Firebase Storage path (e.g. `opportunities/uid/.../video.mov`).
    let videoStoragePath: String?
    /// Tokenized HTTPS URL from Storage `downloadURL()` — **required for investors to play video** (they can’t resolve paths under typical owner-only rules).
    let videoURL: String?
    /// Non-fatal issues from create/update (e.g. upload failures), stored in Firestore `mediaWarnings`.
    let mediaWarnings: [String]
    /// Cloudinary `public_id` values for images (for best-effort delete when the listing is removed).
    let imagePublicIds: [String]
    /// Cloudinary `public_id` for video when hosted on Cloudinary.
    let videoPublicId: String?

    /// Prefer HTTPS URL for playback; fall back to Storage path (works when the current user can read the object).
    var effectiveVideoReference: String? {
        let u = videoURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u, !u.isEmpty { return u }
        let p = videoStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p, !p.isEmpty { return p }
        return nil
    }

    var formattedAmountLKR: String {
        let n = NSNumber(value: amountRequested)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", amountRequested)
    }

    var repaymentLabel: String {
        "\(repaymentTimelineMonths) months"
    }
}
