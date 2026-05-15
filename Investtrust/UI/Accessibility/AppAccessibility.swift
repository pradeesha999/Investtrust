//
//  AppAccessibility.swift
//  Investtrust
//

import SwiftUI
import UIKit

// Haptic feedback helpers used across the app.
// All calls check the in-app haptics preference before firing so the user can turn them off in Settings.
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

// Animation helpers that respect Reduce Motion — used for all screen transitions and state changes
extension Animation {
    // Returns a very fast linear animation when Reduce Motion is on, otherwise a standard ease-in-out
    static func accessibleContentTransition(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.2)
    }

    static func accessibleEmphasis(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.25)
    }
}
