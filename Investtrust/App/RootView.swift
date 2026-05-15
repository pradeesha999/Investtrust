//
//  RootView.swift
//  Investtrust
//

import SwiftUI

// The first view every user sees after launch.
// Switches between the sign-in flow and the main app depending on auth state,
// and shows a full-screen loading overlay while the session is being restored.
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

            // Full-screen spinner shown while Firebase restores the previous session
            if auth.isLoading {
                SessionLoadingOverlay()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.accessibleContentTransition(reduceMotion: reduceMotion), value: auth.isLoading)
        // Clear cached images and video URLs when the user signs out to prevent data leaking between accounts
        .onReceive(NotificationCenter.default.publisher(for: .investtrustSessionMediaDidReset)) { _ in
            CachedImageLoader.clearMemoryCache()
            StorageBackedVideoPlayer.clearURLCache()
        }
    }
}

// Blocks interaction while the app restores an existing Firebase session on launch
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

