//
//  UserProfile.swift
//  Investtrust
//

import Foundation

// Stored in the `users` Firestore collection. Represents a signed-in user who can act as
// an investor, a seeker (opportunity creator), or both depending on their chosen roles.
struct UserProfile: Codable, Equatable {
    // Controls which dashboard tab the app opens by default
    enum ActiveProfile: String, Codable {
        case investor
        case seeker
    }

    var createdAt: Date
    var updatedAt: Date? = nil
    var activeProfile: ActiveProfile
    var roles: Roles        // which modes the user has enabled
    var displayName: String?
    var avatarURL: String?
    var profileDetails: ProfileDetails?  // bio, experience, NIC — required before the user can invest

    // Flags for which modes are active on this account
    struct Roles: Codable, Equatable {
        var investor: Bool
        var seeker: Bool
    }
}
