import FirebaseFirestore
import Foundation

final class InvestmentService {
    private let db = Firestore.firestore()
    
    func fetchInvestments(forInvestor userID: String, limit: Int = 50) async throws -> [InvestmentListing] {
        // Try a couple of known field-name variants.
        let queries: [(String, String?)] = [
            ("investorId", "createdAt"),
            ("investor", "createdAt")
        ]
        
        for (investorField, orderField) in queries {
            do {
                var q: Query = db.collection("investments").whereField(investorField, isEqualTo: userID)
                if let orderField {
                    q = q.order(by: orderField, descending: true)
                }
                let snapshot = try await q.limit(to: limit).getDocuments()
                let rows = snapshot.documents.compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
                if !rows.isEmpty {
                    return rows
                }
            } catch {
                // ignore and try next variant
            }
        }
        
        // Last resort: fetch recent and filter in memory.
        let snapshot = try await db.collection("investments")
            .order(by: "createdAt", descending: true)
            .limit(to: max(limit, 25))
            .getDocuments()
        
        return snapshot.documents
            .filter { doc in
                if let investorId = doc.data()["investorId"] as? String { return investorId == userID }
                if let investorId = doc.data()["investor"] as? String { return investorId == userID }
                return false
            }
            .compactMap { InvestmentListing(id: $0.documentID, data: $0.data()) }
    }
}

