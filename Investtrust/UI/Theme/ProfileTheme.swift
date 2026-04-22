//
//  ProfileTheme.swift
//  Investtrust
//

import SwiftUI

/// Brand accents by active profile: Investor = blue, Opportunity builder (seeker) = pink.
enum ProfileTheme {
    /// #0088FF — Investor mode.
    static let investorBlue = Color(red: 0, green: 0x88 / 255, blue: 1)

    /// Opportunity builder / seeker — matches auth brand pink.
    static let seekerPink = AuthTheme.primaryPink

    static func accent(for profile: UserProfile.ActiveProfile) -> Color {
        profile == .investor ? investorBlue : seekerPink
    }
}
