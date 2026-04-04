//
//  AuthTheme.swift
//  Investtrust
//

import SwiftUI

enum AuthTheme {
    /// Grouped-style field surface (adapts in light / dark mode).
    static var fieldBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// Default field outline; focus uses `primaryPink` instead.
    static var fieldBorder: Color {
        Color(uiColor: .separator)
    }
    static let primaryPink = Color(red: 1, green: 45 / 255, blue: 85 / 255) // #FF2D55
    static let subtitleMuted = Color.secondary
    static let titleLarge: Font = .system(size: 34, weight: .bold)

    /// Soft wash + blurred brand orbs — used behind login / sign-up so screens feel finished without noise.
    static let authGradientTop = Color(red: 0.995, green: 0.985, blue: 0.99)
    static let authGradientMid = Color.white
    static let authGradientBottom = Color(red: 0.96, green: 0.965, blue: 0.98)

    static let fieldCornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 12
}

/// Full-screen background for auth flows: subtle gradient + soft pink glows (constant, not random).
struct AuthScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(AuthTheme.primaryPink.opacity(colorScheme == .dark ? 0.14 : 0.09))
                    .frame(width: min(geo.size.width * 0.95, 340), height: min(geo.size.width * 0.95, 340))
                    .blur(radius: 64)
                    .offset(x: geo.size.width * 0.38, y: -geo.size.height * 0.12)

                Circle()
                    .fill(AuthTheme.primaryPink.opacity(colorScheme == .dark ? 0.09 : 0.055))
                    .frame(width: min(geo.size.width * 0.75, 260), height: min(geo.size.width * 0.75, 260))
                    .blur(radius: 52)
                    .offset(x: -geo.size.width * 0.36, y: geo.size.height * 0.22)

                // Hairline grid for a calm “product” feel (very low contrast).
                GridPattern()
                    .stroke(gridLineColor, lineWidth: 1)
                    .ignoresSafeArea()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.07, green: 0.07, blue: 0.09),
                Color(red: 0.09, green: 0.09, blue: 0.11),
                Color(red: 0.05, green: 0.05, blue: 0.07)
            ]
        }
        return [
            AuthTheme.authGradientTop,
            AuthTheme.authGradientMid,
            AuthTheme.authGradientBottom
        ]
    }

    private var gridLineColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035)
    }
}

private struct GridPattern: Shape {
    private let spacing: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x: CGFloat = 0
        while x <= rect.maxX + spacing {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= rect.maxY + spacing {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

