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

    init() {
        FirebaseApp.configure()
        _authService = State(initialValue: AuthService(userService: UserService()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

