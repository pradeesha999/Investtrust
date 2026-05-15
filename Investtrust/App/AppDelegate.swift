//
//  AppDelegate.swift
//  Investtrust
//

import FirebaseCore
import UIKit

// UIApplicationDelegate adapter used to configure Firebase before the SwiftUI scene loads.
// Keeps Firebase initialisation timing consistent with what Firebase and Google SDKs expect.
final class AppDelegate: NSObject, UIApplicationDelegate {
    override init() {
        super.init()
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        true
    }
}

