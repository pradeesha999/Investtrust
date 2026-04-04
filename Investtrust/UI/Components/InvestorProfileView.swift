import SwiftUI

/// Read-only profile for an investor (or any user id) shown to opportunity seekers.
struct InvestorProfileView: View {
    let userId: String

    private let userService = UserService()

    @State private var profile: UserProfile?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading && profile == nil {
                    ProgressView()
                        .padding(.top, 40)
                } else if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    avatar
                    Text(displayName)
                        .font(.title2.bold())
                    Text("Investor")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("User ID: \(shortId(userId))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: userId) {
            await load()
        }
    }

    private var displayName: String {
        if let n = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return "Investor"
    }

    @ViewBuilder
    private var avatar: some View {
        let size: CGFloat = 96
        if let urlString = profile?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    placeholderCircle(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            placeholderCircle(size: size)
        }
    }

    private func placeholderCircle(size: CGFloat) -> some View {
        Circle()
            .fill(AppTheme.secondaryFill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
    }

    private func shortId(_ id: String) -> String {
        guard id.count > 14 else { return id }
        return "\(id.prefix(8))…\(id.suffix(4))"
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await userService.fetchProfile(userID: userId)
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }
}
