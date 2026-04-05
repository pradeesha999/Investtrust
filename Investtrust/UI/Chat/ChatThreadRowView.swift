import SwiftUI

/// One row in the chat list: counterparty name + avatar (not opportunity title).
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
        return "Member"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !thread.lastMessagePreview.isEmpty {
                    Text(thread.lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
}
