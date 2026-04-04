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
            avatarURL: user.photoURL?.absoluteString
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
        return payload
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

        return UserProfile(
            createdAt: createdAt,
            updatedAt: updatedAt,
            activeProfile: activeProfile,
            roles: .init(investor: investor, seeker: seeker),
            displayName: data["displayName"] as? String,
            avatarURL: data["avatarURL"] as? String
        )
    }
}

