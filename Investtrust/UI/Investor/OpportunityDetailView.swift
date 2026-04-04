import SwiftUI

/// Investor-facing detail screen for a market opportunity (layout inspired by `invest info.svg`).
struct OpportunityDetailView: View {
    let opportunity: OpportunityListing

    @Environment(AuthService.self) private var auth
    private let chatService = ChatService()

    @State private var activeChat: ActiveChatDestination?
    @State private var contactError: String?
    @State private var showContactError = false
    @State private var isOpeningChat = false

    private struct ActiveChatDestination: Identifiable, Hashable {
        let chatId: String
        let title: String
        var id: String { chatId }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(opportunity.title)
                        .font(.title2.bold())
                    if !opportunity.category.isEmpty {
                        Text(opportunity.category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(opportunity.status.uppercased())
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.06), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                divider
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                statBlock(title: "Funding goal", value: "LKR \(opportunity.formattedAmountLKR)")
                divider
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                statBlock(title: "Interest rate", value: "\(formatRate(opportunity.interestRate))%")
                divider
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                statBlock(title: "Repayment", value: opportunity.repaymentLabel)

                if !opportunity.description.isEmpty {
                    divider
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this opportunity")
                            .font(.headline)
                        Text(opportunity.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                }

                if opportunity.videoStoragePath != nil {
                    divider
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    Label("Video attached to this listing", systemImage: "video.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                // Gray placeholder block like the SVG card area (shown when extra context is minimal)
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(height: 192)
                    .overlay(
                        Text("Listing preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                VStack(spacing: 12) {
                    Button {
                        // TODO: invest / express interest flow
                    } label: {
                        Text("Invest")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AuthTheme.primaryPink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(.white)

                    Button {
                        Task { await openChatWithSeeker() }
                    } label: {
                        HStack {
                            if isOpeningChat {
                                ProgressView()
                            }
                            Text("Contact seeker")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 5.25, style: .continuous)
                            .stroke(AuthTheme.primaryPink, lineWidth: 1.5)
                    )
                    .foregroundStyle(AuthTheme.primaryPink)
                    .disabled(isOpeningChat || !canContactSeeker)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Opportunity")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeChat) { dest in
            ChatRoomView(chatId: dest.chatId, title: dest.title)
        }
        .alert("Could not open chat", isPresented: $showContactError) {
            Button("OK") { contactError = nil }
        } message: {
            Text(contactError ?? "")
        }
    }

    private var canContactSeeker: Bool {
        guard let uid = auth.currentUserID else { return false }
        return uid != opportunity.ownerId
    }

    private func openChatWithSeeker() async {
        guard let investorId = auth.currentUserID else {
            contactError = "Sign in to message the seeker."
            showContactError = true
            return
        }
        guard investorId != opportunity.ownerId else { return }

        isOpeningChat = true
        defer { isOpeningChat = false }

        do {
            let chatId = try await chatService.getOrCreateChat(
                opportunityId: opportunity.id,
                seekerId: opportunity.ownerId,
                investorId: investorId,
                opportunityTitle: opportunity.title
            )
            activeChat = ActiveChatDestination(chatId: chatId, title: opportunity.title)
        } catch {
            contactError = error.localizedDescription
            showContactError = true
        }
    }

    private var heroSection: some View {
        Group {
            if opportunity.imageStoragePaths.count > 1 {
                TabView {
                    ForEach(Array(opportunity.imageStoragePaths.enumerated()), id: \.offset) { _, path in
                        StorageBackedAsyncImage(reference: path, height: 280, cornerRadius: 15)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 280)
            } else {
                StorageBackedAsyncImage(
                    reference: opportunity.imageStoragePaths.first,
                    height: 280,
                    cornerRadius: 15
                )
            }
        }
    }

    private func statBlock(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(Int(rate))
        }
        return String(rate)
    }
}

#Preview {
    NavigationStack {
        OpportunityDetailView(
            opportunity: OpportunityListing(
                id: "1",
                ownerId: "x",
                title: "Samsung phone",
                category: "Phone",
                description: "Meow",
                amountRequested: 150_000,
                interestRate: 11,
                repaymentTimelineMonths: 12,
                status: "open",
                createdAt: Date(),
                imageStoragePaths: [],
                videoStoragePath: nil
            )
        )
        .environment(AuthService.previewSignedIn)
    }
}
