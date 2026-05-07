//
//  RootView.swift
//  Investtrust
//

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if auth.isSignedIn {
                    HomeView()
                } else {
                    AuthRootView()
                }
            }
            .animation(.accessibleContentTransition(reduceMotion: reduceMotion), value: auth.isSignedIn)

            if auth.isLoading {
                SessionLoadingOverlay()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.accessibleContentTransition(reduceMotion: reduceMotion), value: auth.isLoading)
        .onReceive(NotificationCenter.default.publisher(for: .investtrustSessionMediaDidReset)) { _ in
            CachedImageLoader.clearMemoryCache()
            StorageBackedVideoPlayer.clearURLCache()
        }
    }
}

private struct SessionLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
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
        .accessibilityHint("Please wait while your session is prepared.")
    }
}

#Preview {
    RootView()
        .environment(AuthService.previewSignedOut)
}

