//
//  StatusBlock.swift
//  Investtrust
//

import SwiftUI

/// Empty, error, and inline status messaging (aligned across dashboards).
struct StatusBlock: View {
    @Environment(AuthService.self) private var auth

    let icon: String
    let title: String
    let message: String
    var iconColor: Color = .secondary
    var iconSize: CGFloat = 40
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(auth.accentColor)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private var statusAccessibilityLabel: String {
        var parts = [title, message]
        if let actionTitle {
            parts.append("Button: \(actionTitle)")
        }
        return parts.joined(separator: ". ")
    }
}
