//
//  UserService.swift
//  Investtrust
//

import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift
import Foundation

final class UserService {
    private let db = Firestore.firestore()
    
    func fetchProfile(userID: String) async throws -> UserProfile? {
        let ref = db.collection("users").document(userID)
        let snapshot = try await ref.getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: UserProfile.self)
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

        try ref.setData(from: profile, merge: true)
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
}

