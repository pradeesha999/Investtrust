//
//  AppAccessibilityPreferences.swift
//  Investtrust
//

import SwiftUI

/// UserDefaults keys for in-app accessibility (Investtrust-only; does not change system Settings).
enum AppAccessibilityPreferences {
    static let hapticsKey = "app.accessibility.hapticsEnabled"
    static let reduceMotionInAppKey = "app.accessibility.reduceMotionInApp"
    static let highContrastKey = "app.accessibility.highContrast"

    /// Default `true` when the key has never been set.
    static var hapticsEnabled: Bool {
        if UserDefaults.standard.object(forKey: hapticsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: hapticsKey)
    }
}

// MARK: - Combined reduce motion (system + in-app toggle)

private struct EffectiveReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// `true` when iOS Reduce Motion is on **or** the in-app “Reduce motion” toggle is on.
    var effectiveReduceMotion: Bool {
        get { self[EffectiveReduceMotionKey.self] }
        set { self[EffectiveReduceMotionKey.self] = newValue }
    }
}

// MARK: - In-app high contrast (Settings → Accessibility)

private struct AppHighContrastEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` when the user enables “Increase contrast in app” in Settings.
    var appHighContrastEnabled: Bool {
        get { self[AppHighContrastEnabledKey.self] }
        set { self[AppHighContrastEnabledKey.self] = newValue }
    }
}
