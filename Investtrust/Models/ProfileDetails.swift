import Foundation

/// Credibility / experience level (stored under `users/{id}.profile`).
enum ProfileExperienceLevel: String, Codable, Sendable, CaseIterable {
    case beginner
    case intermediate
    case experienced

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .experienced: return "Experienced"
        }
    }
}

/// Shared identity & credibility for both investors and opportunity builders (`users/{id}.profile`).
/// Legacy documents may still use `investorProfile`; the app reads both keys.
struct ProfileDetails: Codable, Equatable, Sendable {
    var legalFullName: String?
    var phoneNumber: String?
    var country: String?
    var city: String?
    /// Short bio (2–3 lines): who they are, what they do.
    var shortBio: String?
    var experienceLevel: ProfileExperienceLevel?
    var pastWorkProjects: String?
    /// Admin-controlled later; shown read-only in the app.
    var verificationStatus: VerificationStatus

    init(
        legalFullName: String? = nil,
        phoneNumber: String? = nil,
        country: String? = nil,
        city: String? = nil,
        shortBio: String? = nil,
        experienceLevel: ProfileExperienceLevel? = nil,
        pastWorkProjects: String? = nil,
        verificationStatus: VerificationStatus = .unverified
    ) {
        self.legalFullName = legalFullName
        self.phoneNumber = phoneNumber
        self.country = country
        self.city = city
        self.shortBio = shortBio
        self.experienceLevel = experienceLevel
        self.pastWorkProjects = pastWorkProjects
        self.verificationStatus = verificationStatus
    }

    /// Required before sending an investment request (email comes from the auth account).
    var isCompleteForInvesting: Bool {
        let legal = trimmed(legalFullName)
        let phone = trimmed(phoneNumber)
        let ctry = trimmed(country)
        let cty = trimmed(city)
        let bio = trimmed(shortBio)
        guard !legal.isEmpty, !phone.isEmpty, !ctry.isEmpty, !cty.isEmpty else { return false }
        guard bio.count >= 12 else { return false }
        guard experienceLevel != nil else { return false }
        return true
    }

    var missingProfileHints: [String] {
        var out: [String] = []
        if trimmed(legalFullName).isEmpty { out.append("Legal full name") }
        if trimmed(phoneNumber).isEmpty { out.append("Phone number") }
        if trimmed(country).isEmpty { out.append("Country") }
        if trimmed(city).isEmpty { out.append("City") }
        if trimmed(shortBio).count < 12 { out.append("Short bio (at least 12 characters)") }
        if experienceLevel == nil { out.append("Experience level") }
        return out
    }

    private func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Auto-computed activity (not stored on the user doc).
struct ProfileActivityMetrics: Equatable, Sendable {
    var opportunitiesCreated: Int
    var dealsCompletedAsInvestor: Int
    /// Resolved deals only: completed ÷ (completed + declined/rejected).
    var completionRate: Double
    /// Sum of principal in investments marked completed (as investor).
    var totalInvestedCompletedDeals: Double
}
