//
//  AppDelegate.swift
//  Investtrust
//

import FirebaseCore
import UIKit

/// Bridges SwiftUI lifecycle to `UIApplicationDelegate` for Firebase / Google SDKs.
///
/// `FirebaseApp.configure()` runs here (not only in `App.init`) so it executes after the
/// `@UIApplicationDelegateAdaptor` has instantiated this object. That ordering avoids the common
/// GoogleUtilities message: `App Delegate does not conform to UIApplicationDelegate protocol`
/// (I-SWZ001014) when configure ran before the adaptor wired the delegate.
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

