//
//  InvesttrustApp.swift
//  Investtrust
//

import FirebaseCore
import GoogleSignIn
import SwiftUI

@main
struct InvesttrustApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var authService: AuthService

    @AppStorage(AppearancePreference.storageKey()) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(AppLanguageOption.storageKey()) private var languageRaw: String = AppLanguageOption.system.rawValue

    init() {
        FirebaseApp.configure()
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
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        AppearancePreference(rawValue: appearanceRaw)?.colorScheme
    }

    private var resolvedLocale: Locale {
        AppLanguageOption(rawValue: languageRaw)?.locale ?? Locale.current
    }
}

