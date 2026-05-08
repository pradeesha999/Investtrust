import SwiftUI

/// Read-only profile for any member (e.g. investor viewed by an opportunity builder).
struct PublicProfileView: View {
    struct ChatContext {
        let opportunityId: String
        let seekerId: String?
        let opportunityTitle: String
    }

    let userId: String
    var chatContext: ChatContext? = nil

    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var tabRouter: MainTabRouter
    @Environment(\.dismiss) private var dismiss
    private let userService = UserService()
    private let chatService = ChatService()

    @State private var profile: UserProfile?
    @State private var metrics: ProfileActivityMetrics?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var chatError: String?

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
                    Text(metrics == nil ? "Community member" : "Active member")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    verificationBadge

                    if let d = profile?.profileDetails {
                        identitySection(d)
                        credibilitySection(d)
                    } else {
                        Text("This member hasn’t added profile details yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let m = metrics {
                        metricsSection(m)
                    }

                    if chatContext != nil {
                        Button {
                            Task { await openChatWithMember() }
                        } label: {
                            Label("Chat with investor", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: AppTheme.minTapTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(auth.accentColor)
                    }

                    if let chatError {
                        Text(chatError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

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
        if let legal = profile?.profileDetails?.legalFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !legal.isEmpty {
            return legal
        }
        if let n = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return "Member"
    }

    @ViewBuilder
    private var verificationBadge: some View {
        let status = profile?.profileDetails?.verificationStatus ?? .unverified
        HStack(spacing: 6) {
            Image(systemName: status == .verified ? "checkmark.seal.fill" : "questionmark.circle.fill")
                .foregroundStyle(status == .verified ? .green : .secondary)
            Text(status == .verified ? "Verified" : "Unverified")
                .font(.caption.weight(.semibold))
                .foregroundStyle(status == .verified ? .green : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.secondaryFill, in: Capsule())
    }

    private func identitySection(_ d: ProfileDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact & location")
                .font(.headline)
            if let phone = d.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                labeledRow("Phone", phone)
            }
            let loc = [d.city, d.country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !loc.isEmpty {
                labeledRow("Location", loc.joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func credibilitySection(_ d: ProfileDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)
            if let bio = d.shortBio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let exp = d.experienceLevel {
                labeledRow("Experience", exp.displayName)
            }
            if let past = d.pastWorkProjects?.trimmingCharacters(in: .whitespacesAndNewlines), !past.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Past work / projects")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(past)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func metricsSection(_ m: ProfileActivityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity (auto)")
                .font(.headline)
            labeledRow("Opportunities created", "\(m.opportunitiesCreated)")
            labeledRow("Completed deals (as investor)", "\(m.dealsCompletedAsInvestor)")
            labeledRow("Completion rate", "\(Int(m.completionRate * 100))%")
            labeledRow("Total invested (completed)", "LKR \(formatLKR(m.totalInvestedCompletedDeals))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .appCardShadow()
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatLKR(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(format: "%.0f", v)
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
            metrics = try await userService.fetchProfileActivityMetrics(userID: userId)
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func openChatWithMember() async {
        guard let context = chatContext else { return }
        guard let seekerId = context.seekerId ?? auth.currentUserID else {
            await MainActor.run {
                chatError = "Please sign in again."
            }
            return
        }
        do {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: context.opportunityId,
                seekerId: seekerId,
                investorId: userId,
                opportunityTitle: context.opportunityTitle
            )
            await MainActor.run {
                tabRouter.pendingChatDeepLink = ChatDeepLink(chatId: chatId, inquirySnapshot: nil)
                tabRouter.selectedTab = .chat
                dismiss()
            }
        } catch {
            await MainActor.run {
                chatError = (error as NSError).localizedDescription
            }
        }
    }
}
