//
//  AccessibilityEnvironmentRoot.swift
//  Investtrust
//

import SwiftUI

// Wraps the app's root view to inject in-app accessibility preferences into the SwiftUI environment.
// Combines system settings (e.g. iOS Reduce Motion) with the user's in-app toggles from Settings.
struct AccessibilityEnvironmentRoot<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(AppAccessibilityPreferences.reduceMotionInAppKey) private var reduceMotionInApp = false
    @AppStorage(AppAccessibilityPreferences.highContrastKey) private var highContrastInApp = false

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.effectiveReduceMotion, systemReduceMotion || reduceMotionInApp)
            .environment(\.appHighContrastEnabled, highContrastInApp)
            .contrast(highContrastInApp ? 1.12 : 1.0)
    }
}
