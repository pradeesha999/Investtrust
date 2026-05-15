//
//  AuthRootView.swift
//  Investtrust
//

import SwiftUI

// Navigation root for the unauthenticated flow — presents LoginView first, then allows push to SignUpView
struct AuthRootView: View {
    var body: some View {
        NavigationStack {
            LoginView()
        }
    }
}

#Preview {
    AuthRootView()
        .environment(AuthService.previewSignedOut)
}

