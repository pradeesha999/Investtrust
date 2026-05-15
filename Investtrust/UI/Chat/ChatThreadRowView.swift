import SwiftUI

// A single row in the Chat tab list — shows the other person's name, avatar, and last message preview
struct ChatThreadRowView: View {
    let thread: ChatThread
    let currentUserId: String?

    private let userService = UserService()

    @State private var profile: UserProfile?

    private var counterpartyId: String? {
        thread.counterpartyId(currentUserId: currentUserId)
    }

    private var displayName: String {
        if let n = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return "Conversation"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if let lastMessageAt = thread.lastMessageAt {
                        Text(shortTime(lastMessageAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !thread.lastMessagePreview.isEmpty {
                    Text(thread.lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: counterpartyId) {
            await loadProfile()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = profile?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(AppTheme.secondaryFill)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }

    private func loadProfile() async {
        guard let id = counterpartyId, !id.isEmpty else {
            profile = nil
            return
        }
        do {
            profile = try await userService.fetchProfile(userID: id)
        } catch {
            profile = nil
        }
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
