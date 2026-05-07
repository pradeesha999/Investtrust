import SwiftUI

struct InAppNotificationsView: View {
    let notifications: [InAppNotification]
    var onRefresh: () async -> Void
    var onTapNotification: (InAppNotification) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if notifications.isEmpty {
                    ContentUnavailableView(
                        "No notifications",
                        systemImage: "bell",
                        description: Text("You’re all caught up.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(notifications) { item in
                                Button {
                                    onTapNotification(item)
                                    dismiss()
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle()
                                            .fill(item.kind == .actionRequired ? Color.orange : Color.blue.opacity(0.7))
                                            .frame(width: 8, height: 8)
                                            .padding(.top, 6)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(item.message)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(Self.dateText(item.createdAt))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.tertiary)
                                            .padding(.top, 4)
                                    }
                                    .padding(12)
                                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                                            .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(AppTheme.screenPadding)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await onRefresh() }
        }
    }

    private static func dateText(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }
}
