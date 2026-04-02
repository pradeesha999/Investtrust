//
//  RootView.swift
//  Investtrust
//

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.isSignedIn {
                HomeView()
            } else {
                AuthRootView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isSignedIn)
    }
}

#Preview {
    RootView()
        .environment(AuthService.previewSignedOut)
}

