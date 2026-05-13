import FirebaseFirestore
import Foundation

/// Reads `offers/{offerId}` documents (top-level collection, same pattern as `investments` / `opportunities`).
final class OfferService {
    private let db = Firestore.firestore()

    /// Loads offer rows for an opportunity. **Must** filter by `listingOwnerSeekerId` (same as `auth.uid` when the seeker loads their listing) so Firestore rules can prove every matching doc passes `offers` read rules.
    func fetchOffersKeyedByInvestmentId(opportunityId: String, listingOwnerSeekerId: String) async throws -> [String: FirestoreInvestorOffer] {
        let snap = try await db.collection("offers")
            .whereField("opportunityId", isEqualTo: opportunityId)
            .whereField("seekerId", isEqualTo: listingOwnerSeekerId)
            .limit(to: 120)
            .getDocuments(source: .server)

        var best: [String: (offer: FirestoreInvestorOffer, sortDate: Date)] = [:]
        for doc in snap.documents {
            guard let offer = FirestoreInvestorOffer(id: doc.documentID, data: doc.data()) else { continue }
            let sortDate = offer.updatedAt ?? offer.createdAt ?? .distantPast
            if let existing = best[offer.investmentId] {
                if sortDate > existing.sortDate {
                    best[offer.investmentId] = (offer, sortDate)
                }
            } else {
                best[offer.investmentId] = (offer, sortDate)
            }
        }
        return Dictionary(uniqueKeysWithValues: best.map { ($0.key, $0.value.offer) })
    }

    /// Latest offer for an investment when the viewer is the **investor** or **seeker** on that row (required for rules).
    func fetchLatestOfferForInvestment(investmentId: String, viewerUid: String) async throws -> FirestoreInvestorOffer? {
        let asSeeker = try await db.collection("offers")
            .whereField("investmentId", isEqualTo: investmentId)
            .whereField("seekerId", isEqualTo: viewerUid)
            .limit(to: 25)
            .getDocuments(source: .server)
        let asInvestor = try await db.collection("offers")
            .whereField("investmentId", isEqualTo: investmentId)
            .whereField("investorId", isEqualTo: viewerUid)
            .limit(to: 25)
            .getDocuments(source: .server)
        var merged: [String: QueryDocumentSnapshot] = [:]
        for d in asSeeker.documents { merged[d.documentID] = d }
        for d in asInvestor.documents { merged[d.documentID] = d }
        let offers = merged.values.compactMap { FirestoreInvestorOffer(id: $0.documentID, data: $0.data()) }
        return offers.max { a, b in
            let la = a.updatedAt ?? a.createdAt ?? .distantPast
            let lb = b.updatedAt ?? b.createdAt ?? .distantPast
            return la < lb
        }
    }
}
