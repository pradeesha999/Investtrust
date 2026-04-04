import SwiftUI

struct InvestorMarketView: View {
    @Environment(AuthService.self) private var auth

    @State private var investments: [InvestmentListing] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""

    private let investmentService = InvestmentService()

    var filteredInvestments: [InvestmentListing] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return investments
        }
        let q = searchText.lowercased()
        return investments.filter { $0.opportunityTitle.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    searchPill
                    
                    if isLoading && investments.isEmpty {
                        ProgressView("Loading investments…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    } else if let loadError {
                        errorState(loadError)
                    } else if filteredInvestments.isEmpty {
                        emptyState
                    } else {
                        investmentCards
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invest")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 48, height: 48)
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Your investments")
                    .font(.headline)
                Text("Track deals and agreements")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }

    private var searchPill: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by listing name", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.06), in: Capsule())
    }

    private var investmentCards: some View {
        LazyVStack(spacing: 14) {
            ForEach(filteredInvestments) { inv in
                InvestmentCard(inv: inv)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No investments found")
                .font(.headline)
            Text("When you finalize a deal, it will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't load investments")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AuthTheme.primaryPink)
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        
        guard let userID = auth.currentUserID else {
            loadError = "Please sign in again."
            return
        }
        
        do {
            investments = try await investmentService.fetchInvestments(forInvestor: userID)
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }
}

private struct InvestmentCard: View {
    let inv: InvestmentListing
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                media
                    .frame(width: 110, height: 110)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(inv.opportunityTitle.isEmpty ? "Investment" : inv.opportunityTitle)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(inv.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amount: LKR \(format(inv.investmentAmount))")
                            .font(.subheadline)
                        Text("Interest: \(inv.interestLabel)")
                            .font(.subheadline)
                        Text("Timeline: \(inv.timelineLabel)")
                            .font(.subheadline)
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button {
                    // TODO: route to chat screen once chat is implemented.
                } label: {
                    Text("Chat")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 10)
                .background(AuthTheme.primaryPink, in: Capsule())
                .foregroundStyle(.white)
                
                Button {
                    // TODO: route to agreement documents once implemented.
                } label: {
                    Text("Agreement")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 10)
                .background(AuthTheme.primaryPink, in: Capsule())
                .foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    @ViewBuilder
    private var media: some View {
        if let first = inv.imageURLs.first, let url = URL(string: first) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color(.systemGray4)
            }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemGray4))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }
    }
    
    private func format(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? String(Int(v))
    }
}

#Preview {
    InvestorMarketView()
        .environment(AuthService.previewSignedIn)
}
