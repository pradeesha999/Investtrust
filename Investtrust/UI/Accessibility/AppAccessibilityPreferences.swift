//
//  AppAccessibilityPreferences.swift
//  Investtrust
//

import SwiftUI

// In-app accessibility settings that complement the system accessibility options.
// Stored in UserDefaults and surfaced as toggles on the Settings screen.
enum AppAccessibilityPreferences {
    static let hapticsKey = "app.accessibility.hapticsEnabled"
    static let reduceMotionInAppKey = "app.accessibility.reduceMotionInApp"
    static let highContrastKey = "app.accessibility.highContrast"

    // Defaults to true on first launch — user can turn it off in Settings
    static var hapticsEnabled: Bool {
        if UserDefaults.standard.object(forKey: hapticsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: hapticsKey)
    }
}

// Environment key combining system and in-app reduce motion preferences

private struct EffectiveReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    // `true` when iOS Reduce Motion is on **or** the in-app “Reduce motion” toggle is on.
    var effectiveReduceMotion: Bool {
        get { self[EffectiveReduceMotionKey.self] }
        set { self[EffectiveReduceMotionKey.self] = newValue }
    }
}

// Environment key for the in-app high contrast toggle in Settings

private struct AppHighContrastEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    // `true` when the user enables “Increase contrast in app” in Settings.
    var appHighContrastEnabled: Bool {
        get { self[AppHighContrastEnabledKey.self] }
        set { self[AppHighContrastEnabledKey.self] = newValue }
    }
}
