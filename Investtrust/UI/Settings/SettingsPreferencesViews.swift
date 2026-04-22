import SwiftUI

// MARK: - Appearance

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func storageKey() -> String { "settings.appearance" }
}

struct SettingsAppearanceView: View {
    @AppStorage(AppearancePreference.storageKey()) private var appearanceRaw: String = AppearancePreference.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.title).tag(pref.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Choose how Investtrust looks. System follows your iPhone’s Light / Dark mode.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Language

enum AppLanguageOption: String, CaseIterable, Identifiable {
    case system
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System default"
        case .en: return "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return Locale.current
        case .en: return Locale(identifier: "en")
        }
    }

    static func storageKey() -> String { "settings.language" }
}

struct SettingsLanguageView: View {
    @AppStorage(AppLanguageOption.storageKey()) private var languageRaw: String = AppLanguageOption.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $languageRaw) {
                    ForEach(AppLanguageOption.allCases) { opt in
                        Text(opt.title).tag(opt.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("More languages will appear as the app is localized. Dates and numbers follow this setting when not using system default.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Accessibility

struct SettingsAccessibilityView: View {
    @AppStorage(AppAccessibilityPreferences.hapticsKey) private var hapticsEnabled = true
    @AppStorage(AppAccessibilityPreferences.reduceMotionInAppKey) private var reduceMotionInApp = false
    @AppStorage(AppAccessibilityPreferences.highContrastKey) private var highContrastInApp = false

    var body: some View {
        Form {
            Section {
                Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                    .accessibilityHint("Vibration on actions like sending a message or switching profile.")

                Toggle("Reduce Motion", isOn: $reduceMotionInApp)
                    .accessibilityHint("Less animation in Investtrust. System Reduce Motion in Settings still applies.")

                Toggle("Increase Contrast", isOn: $highContrastInApp)
                    .accessibilityHint("Stronger contrast for text and controls in this app only.")
            } footer: {
                Text("These options apply only to Investtrust.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}
