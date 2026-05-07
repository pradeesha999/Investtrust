//
//  AppAccessibility.swift
//  Investtrust
//

import SwiftUI
import UIKit

// MARK: - Haptics (respects Settings → Sounds & Haptics)

/// Light tactile feedback for successful actions. The system suppresses this when haptics are disabled.
enum AppHaptics {
    static func selection() {
        guard AppAccessibilityPreferences.hapticsEnabled else { return }
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        g.selectionChanged()
    }

    static func lightImpact() {
        guard AppAccessibilityPreferences.hapticsEnabled else { return }
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    static func success() {
        guard AppAccessibilityPreferences.hapticsEnabled else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    static func warning() {
        guard AppAccessibilityPreferences.hapticsEnabled else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.warning)
    }
}

// MARK: - Animation helpers (pass `effectiveReduceMotion` from the environment)

extension Animation {
    /// Prefer this instead of long ease-in-out when the user has Reduce Motion enabled.
    static func accessibleContentTransition(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.2)
    }

    static func accessibleEmphasis(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.25)
    }
}
