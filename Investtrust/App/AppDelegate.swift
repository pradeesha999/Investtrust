//
//  AppDelegate.swift
//  Investtrust
//

import UIKit

/// Bridges SwiftUI lifecycle to `UIApplicationDelegate` so Firebase / GoogleUtilities swizzling sees a normal delegate.
@objc(AppDelegate)
final class AppDelegate: NSObject, UIApplicationDelegate {
    @objc
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}

