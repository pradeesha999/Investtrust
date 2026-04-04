//
//  AppTheme.swift
//  Investtrust
//

import SwiftUI

/// Shared tokens for non-auth surfaces (cards, spacing, elevation).
enum AppTheme {
    static var accent: Color { AuthTheme.primaryPink }

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

    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let stackSpacing: CGFloat = 14
}

extension View {
    /// Subtle card elevation that works in light and dark mode.
    func appCardShadow() -> some View {
        shadow(color: Color.primary.opacity(0.08), radius: 10, x: 0, y: 3)
    }
}
