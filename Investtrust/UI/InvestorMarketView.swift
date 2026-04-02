import SwiftUI

struct InvestorMarketView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Investor Market")
                    .font(.title3.bold())
                Text("Browse open opportunities and invest directly or negotiate in chat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coming next")
                                .font(.headline)
                            Text("We'll show all open opportunities here with filters and invest actions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14),
                        alignment: .topLeading
                    )
                    .frame(height: 140)
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invest")
        }
    }
}

#Preview {
    InvestorMarketView()
}
