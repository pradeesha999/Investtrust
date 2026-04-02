//
//  UserProfile.swift
//  Investtrust
//

import Foundation

struct UserProfile: Codable, Equatable {
    enum ActiveProfile: String, Codable {
        case investor
        case seeker
    }

    var createdAt: Date
    var updatedAt: Date? = nil
    var activeProfile: ActiveProfile
    var roles: Roles
    var displayName: String?
    var avatarURL: String?

    struct Roles: Codable, Equatable {
        var investor: Bool
        var seeker: Bool
    }
}

