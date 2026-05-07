//
//  AppTheme.swift
//  Investtrust
//

import SwiftUI

/// Shared tokens for non-auth surfaces (cards, spacing, elevation).
enum AppTheme {
    /// Seeker default when `AuthService` is unavailable (e.g. some previews). Prefer `auth.accentColor`.
    static var accentFallback: Color { ProfileTheme.seekerBlue }

    /// Elevated cards on `systemGroupedBackground`.
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
    /// Subtle card elevation that works in light and dark mode.
    func appCardShadow() -> some View {
        shadow(color: Color.primary.opacity(0.08), radius: 10, x: 0, y: 3)
    }

    /// Lightweight, HIG-friendly section header subtitle style.
    func appSectionSubtitleStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
    }
}
