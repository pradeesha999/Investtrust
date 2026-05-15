//
//  AppTheme.swift
//  Investtrust
//

import SwiftUI

// Design tokens used across all non-auth screens — card styles, spacing, corner radii, and tap targets
enum AppTheme {
    // Fallback accent when AuthService isn't available (e.g. Xcode previews). Use auth.accentColor at runtime.
    static var accentFallback: Color { ProfileTheme.seekerBlue }

    // White card surface that sits on top of the grouped background
    static var cardBackground: Color {
        Color(uiColor: .systemBackground)
    }

    static var secondaryFill: Color {
        Color(uiColor: .secondarySystemFill)
    }

    static var tertiaryFill: Color {
        Color(uiColor: .tertiarySystemFill)
    }

    static let cardCornerRadius: CGFloat = 20
    static let controlCornerRadius: CGFloat = 12

    static let spacingXS: CGFloat = 8
    static let spacingSM: CGFloat = 12
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let stackSpacing: CGFloat = 14

    static let minTapTarget: CGFloat = 44
}

extension View {
    // Adds a subtle drop shadow to deal cards that looks natural in both light and dark mode
    func appCardShadow() -> some View {
        shadow(color: Color.primary.opacity(0.08), radius: 10, x: 0, y: 3)
    }

    // Dimmed spinner overlay shown while a payment proof or principal photo is uploading
    func imageUploadProgressOverlay(isPresented: Bool, cornerRadius: CGFloat = AppTheme.cardCornerRadius) -> some View {
        overlay {
            if isPresented {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                    ProgressView()
                        .controlSize(.regular)
                }
                .allowsHitTesting(true)
                .accessibilityLabel("Uploading image")
            }
        }
    }
}
