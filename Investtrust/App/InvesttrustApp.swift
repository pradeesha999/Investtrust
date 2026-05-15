//
//  InvesttrustApp.swift
//  Investtrust
//

import FirebaseCore
import GoogleSignIn
import SwiftUI

// App entry point. Configures Firebase, creates the shared AuthService,
// and applies the user's chosen appearance and language preferences across the whole app.
@main
struct InvesttrustApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var authService: AuthService

    // Persisted appearance / language settings from Settings
    @AppStorage(AppearancePreference.storageKey()) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(AppLanguageOption.storageKey()) private var languageRaw: String = AppLanguageOption.system.rawValue

    init() {
        // AppDelegate already configures Firebase on device; this guard keeps Xcode previews working too
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        _authService = State(initialValue: AuthService(userService: UserService()))
    }

    var body: some Scene {
        WindowGroup {
            AccessibilityEnvironmentRoot {
                RootView()
                    .environment(authService)
                    .preferredColorScheme(resolvedColorScheme)
                    .environment(\.locale, resolvedLocale)
            }
            // Hand Google Sign-In redirect URLs back to the SDK
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    // Convert the stored raw string to a SwiftUI ColorScheme (nil = follow system)
    private var resolvedColorScheme: ColorScheme? {
        AppearancePreference(rawValue: appearanceRaw)?.colorScheme
    }

    // Convert the stored raw string to a Locale (nil = device default)
    private var resolvedLocale: Locale {
        AppLanguageOption(rawValue: languageRaw)?.locale ?? Locale.current
    }
}

