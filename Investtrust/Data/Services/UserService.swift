//
//  UserService.swift
//  Investtrust
//

import FirebaseAuth
import FirebaseFirestore
import Foundation

final class UserService {
    private let db = Firestore.firestore()

    func fetchProfile(userID: String) async throws -> UserProfile? {
        let ref = db.collection("users").document(userID)
        let snapshot = try await ref.getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return Self.userProfile(from: data)
    }

    /// Resolves a profile even when the users doc id is not the Firebase uid
    /// (legacy datasets may store uid under a field like `uid` / `userId` / `id`).
    func fetchProfileResolvingLegacyIDs(userID: String) async throws -> UserProfile? {
        if let direct = try await fetchProfile(userID: userID) {
            return direct
        }

        let keys = ["uid", "userId", "id"]
        for key in keys {
            let query = db.collection("users")
                .whereField(key, isEqualTo: userID)
                .limit(to: 1)
            let snapshot = try await query.getDocuments()
            if let doc = snapshot.documents.first,
               let parsed = Self.userProfile(from: doc.data()) {
                return parsed
            }
        }
        return nil
    }

    func ensureUserDocumentExists(for user: User) async throws {
        let ref = db.collection("users").document(user.uid)
        let snapshot = try await ref.getDocument()
        if snapshot.exists {
            return
        }

        let profile = UserProfile(
            createdAt: Date(),
            activeProfile: .investor,
            roles: .init(investor: true, seeker: true),
            displayName: user.displayName,
            avatarURL: user.photoURL?.absoluteString,
            profileDetails: nil
        )

        try await ref.setData(Self.firestorePayload(for: profile), merge: true)
    }

    func updateActiveProfile(userID: String, activeProfile: UserProfile.ActiveProfile) async throws {
        let ref = db.collection("users").document(userID)
        try await ref.setData(
            [
                "activeProfile": activeProfile.rawValue,
                "updatedAt": Timestamp(date: Date())
            ],
            merge: true
        )
    }

    /// Persists shared profile fields under `profile` (merge). Legacy `investorProfile` is no longer written.
    func saveProfileDetails(userID: String, details: ProfileDetails) async throws {
        let ref = db.collection("users").document(userID)
        var payload: [String: Any] = [
            "profile": Self.profileDetailsPayload(details),
            "updatedAt": Timestamp(date: Date())
        ]
        if let legal = details.legalFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !legal.isEmpty {
            payload["displayName"] = legal
        }
        try await ref.setData(payload, merge: true)
    }

    func updateAvatarURL(userID: String, url: String?) async throws {
        let ref = db.collection("users").document(userID)
        if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await ref.setData(
                ["avatarURL": url, "updatedAt": Timestamp(date: Date())],
                merge: true
            )
        } else {
            try await ref.setData(
                ["avatarURL": FieldValue.delete(), "updatedAt": Timestamp(date: Date())],
                merge: true
            )
        }
    }

    /// Backfills profile identity fields from Firebase Auth (e.g. Google photo/name)
    /// without overriding values the user already customized in-app.
    func syncIdentityFromAuthIfNeeded(for user: User) async throws {
        let ref = db.collection("users").document(user.uid)
        let snapshot = try await ref.getDocument()
        let data = snapshot.data() ?? [:]

        let existingName = (data["displayName"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let existingAvatar = (data["avatarURL"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var payload: [String: Any] = [:]
        if existingName.isEmpty,
           let authName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authName.isEmpty {
            payload["displayName"] = authName
        }
        if existingAvatar.isEmpty,
           let authPhoto = user.photoURL?.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines),
           !authPhoto.isEmpty {
            payload["avatarURL"] = authPhoto
        }

        guard !payload.isEmpty else { return }
        payload["updatedAt"] = Timestamp(date: Date())
        try await ref.setData(payload, merge: true)
    }

    /// Opportunity listings created + investment stats (shown on public profile).
    func fetchProfileActivityMetrics(userID: String) async throws -> ProfileActivityMetrics {
        let opportunityService = OpportunityService()
        let investmentService = InvestmentService()

        let opportunitiesCreated = try await opportunityService.countOpportunitiesForOwner(ownerId: userID)
        let rows = try await investmentService.fetchInvestments(forInvestor: userID, limit: 500)

        let completed = rows.filter { $0.status.lowercased() == "completed" }
        let declined = rows.filter { ["declined", "rejected"].contains($0.status.lowercased()) }
        let resolved = completed.count + declined.count
        let completionRate = resolved > 0 ? Double(completed.count) / Double(resolved) : 0
        let totalInvested = completed.reduce(0.0) { $0 + $1.investmentAmount }

        return ProfileActivityMetrics(
            opportunitiesCreated: opportunitiesCreated,
            dealsCompletedAsInvestor: completed.count,
            completionRate: completionRate,
            totalInvestedCompletedDeals: totalInvested
        )
    }

    private static func firestorePayload(for profile: UserProfile) -> [String: Any] {
        var payload: [String: Any] = [
            "createdAt": Timestamp(date: profile.createdAt),
            "activeProfile": profile.activeProfile.rawValue,
            "roles": [
                "investor": profile.roles.investor,
                "seeker": profile.roles.seeker
            ]
        ]
        if let updatedAt = profile.updatedAt {
            payload["updatedAt"] = Timestamp(date: updatedAt)
        }
        if let displayName = profile.displayName {
            payload["displayName"] = displayName
        }
        if let avatarURL = profile.avatarURL {
            payload["avatarURL"] = avatarURL
        }
        if let d = profile.profileDetails {
            payload["profile"] = profileDetailsPayload(d)
        }
        return payload
    }

    private static func profileDetailsPayload(_ d: ProfileDetails) -> [String: Any] {
        var m: [String: Any] = [
            "verificationStatus": d.verificationStatus.rawValue
        ]
        if let v = d.legalFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            m["legalFullName"] = v
        }
        if let v = d.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            m["phoneNumber"] = v
        }
        if let v = d.country?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            m["country"] = v
        }
        if let v = d.city?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            m["city"] = v
        }
        if let v = d.shortBio?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            m["shortBio"] = v
        }
        if let v = d.experienceLevel {
            m["experienceLevel"] = v.rawValue
        }
        if let v = d.pastWorkProjects?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            m["pastWorkProjects"] = v
        }
        return m
    }

    private static func userProfile(from data: [String: Any]) -> UserProfile? {
        let createdAt: Date = {
            if let ts = data["createdAt"] as? Timestamp {
                return ts.dateValue()
            }
            return Date()
        }()
        let updatedAt: Date? = (data["updatedAt"] as? Timestamp)?.dateValue()

        let activeRaw = data["activeProfile"] as? String ?? UserProfile.ActiveProfile.investor.rawValue
        let activeProfile = UserProfile.ActiveProfile(rawValue: activeRaw) ?? .investor

        var investor = true
        var seeker = true
        if let roles = data["roles"] as? [String: Any] {
            if let v = roles["investor"] as? Bool { investor = v }
            if let v = roles["seeker"] as? Bool { seeker = v }
        }

        let profileDetails: ProfileDetails? = {
            if let m = data["profile"] as? [String: Any] {
                return parseProfileDetailsMap(m)
            }
            if let m = data["investorProfile"] as? [String: Any] {
                return parseProfileDetailsMap(m)
            }
            if let m = data["seekerProfile"] as? [String: Any] {
                return parseProfileDetailsMap(m)
            }
            if let lifted = liftedProfileMap(from: data) {
                return parseProfileDetailsMap(lifted)
            }
            return nil
        }()

        let displayName: String? = {
            let direct = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let direct, !direct.isEmpty { return direct }
            let fallbacks = [
                data["name"] as? String,
                data["fullName"] as? String,
                data["legalFullName"] as? String,
                (data["profile"] as? [String: Any])?["legalFullName"] as? String,
                (data["investorProfile"] as? [String: Any])?["legalFullName"] as? String,
                (data["seekerProfile"] as? [String: Any])?["legalFullName"] as? String
            ]
            for raw in fallbacks {
                let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty { return trimmed }
            }
            return nil
        }()

        return UserProfile(
            createdAt: createdAt,
            updatedAt: updatedAt,
            activeProfile: activeProfile,
            roles: .init(investor: investor, seeker: seeker),
            displayName: displayName,
            avatarURL: (
                (data["avatarURL"] as? String)
                ?? (data["photoURL"] as? String)
                ?? (data["photoUrl"] as? String)
            ),
            profileDetails: profileDetails
        )
    }

    private static func liftedProfileMap(from data: [String: Any]) -> [String: Any]? {
        var out: [String: Any] = [:]
        let keys = [
            "legalFullName",
            "phoneNumber",
            "country",
            "city",
            "shortBio",
            "experienceLevel",
            "pastWorkProjects",
            "verificationStatus"
        ]
        for key in keys {
            if let value = data[key] {
                out[key] = value
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func parseProfileDetailsMap(_ m: [String: Any]) -> ProfileDetails {
        let legal = m["legalFullName"] as? String
        let phone = m["phoneNumber"] as? String
        let country = m["country"] as? String
        let city = m["city"] as? String
        let bio = m["shortBio"] as? String
        let past = m["pastWorkProjects"] as? String
        let expRaw = m["experienceLevel"] as? String
        let exp = expRaw.flatMap { ProfileExperienceLevel(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        let ver = VerificationStatus.parse(m["verificationStatus"] as? String)
        return ProfileDetails(
            legalFullName: legal,
            phoneNumber: phone,
            country: country,
            city: city,
            shortBio: bio,
            experienceLevel: exp,
            pastWorkProjects: past,
            verificationStatus: ver
        )
    }
}
