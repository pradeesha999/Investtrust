//
//  RootView.swift
//  Investtrust
//

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack {
            Group {
                if auth.isSignedIn {
                    HomeView()
                } else {
                    AuthRootView()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: auth.isSignedIn)

            if auth.isLoading {
                SessionLoadingOverlay()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: auth.isLoading)
    }
}

private struct SessionLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AuthTheme.primaryPink)
                Text("Signing you in…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AuthTheme.subtitleMuted)
            }
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signing you in")
    }
}

#Preview {
    RootView()
        .environment(AuthService.previewSignedOut)
}

