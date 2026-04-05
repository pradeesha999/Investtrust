import SwiftUI
import UIKit

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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Investtrust respects your system settings: Dynamic Type, Bold Text, Reduce Motion, and other iOS accessibility features apply throughout the app.")
                    .font(.body)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips")
                        .font(.headline)
                    bullet("Use Settings → Display & Brightness → Text Size to change text size globally.")
                    bullet("Use Settings → Accessibility for VoiceOver, contrast, and more.")
                }

                Link(destination: URL(string: "https://support.apple.com/accessibility")!) {
                    Label("Apple Accessibility overview", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(AppTheme.accent)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open app settings", systemImage: "gearshape")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
