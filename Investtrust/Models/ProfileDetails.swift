import Foundation

// User profile data stored under users/{id}.profile in Firestore.
// Must be filled in before an investor can send a request (checked by isCompleteForInvesting).

// Self-reported experience label shown on the investor's public profile
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

// Identity and credibility details for both investors and seekers
struct ProfileDetails: Codable, Equatable, Sendable {
    var legalFullName: String?
    var phoneNumber: String?
    var country: String?
    var city: String?
    var shortBio: String?           // 2-3 line summary shown on the public profile card
    var experienceLevel: ProfileExperienceLevel?
    var pastWorkProjects: String?
    var verificationStatus: VerificationStatus  // set by admin; shown as a badge on the profile

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

    // Returns true only when all required fields are filled in — gates the "Invest" button
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

// Computed from Firestore queries at runtime — not stored on the user document
struct ProfileActivityMetrics: Equatable, Sendable {
    var opportunitiesCreated: Int
    var dealsCompletedAsInvestor: Int
    var completionRate: Double              // completed deals ÷ (completed + declined)
    var totalInvestedCompletedDeals: Double // total principal across all completed investments
}
