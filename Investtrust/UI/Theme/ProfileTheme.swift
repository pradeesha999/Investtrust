//
//  ProfileTheme.swift
//  Investtrust
//

import SwiftUI

// Brand accent colours that change based on the user's active profile mode:
// red for the investor side, blue for the seeker (opportunity builder) side
enum ProfileTheme {
    static let investorRed = Color(red: 1, green: 0x2D / 255, blue: 0x55 / 255)  // #FF2D55
    static let seekerBlue = Color(red: 0, green: 0x88 / 255, blue: 1)             // #0088FF

    // Returns the correct accent colour for a given profile mode
    static func accent(for profile: UserProfile.ActiveProfile) -> Color {
        profile == .investor ? investorRed : seekerBlue
    }
}
