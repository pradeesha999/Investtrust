import SwiftUI

struct ChatListView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Chats")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Negotiation and investment chats will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        Text("No chats yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    )
                    .frame(height: 120)
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chat")
        }
    }
}

#Preview {
    ChatListView()
}
