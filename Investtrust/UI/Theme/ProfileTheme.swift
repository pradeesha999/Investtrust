//
//  ProfileTheme.swift
//  Investtrust
//

import SwiftUI

/// Brand accents by active profile: Investor = red, Opportunity builder (seeker) = blue.
enum ProfileTheme {
    /// #FF2D55 — Investor mode.
    static let investorRed = Color(red: 1, green: 0x2D / 255, blue: 0x55 / 255)

    /// #0088FF — Opportunity builder / seeker mode.
    static let seekerBlue = Color(red: 0, green: 0x88 / 255, blue: 1)

    static func accent(for profile: UserProfile.ActiveProfile) -> Color {
        profile == .investor ? investorRed : seekerBlue
    }
}
