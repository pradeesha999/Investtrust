import Foundation

/// Maps Firestore / gRPC errors to actionable copy for in-app alerts.
enum FirestoreUserFacingMessage {
    /// Standard Firestore iOS error domain (see `FirestoreErrorDomain`).
    private static let firestoreDomain = "FIRFirestoreErrorDomain"

    static func text(for error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == firestoreDomain || ns.domain.contains("Firestore") else {
            return ns.localizedDescription
        }
        switch ns.code {
        case 7: // PERMISSION_DENIED
            return """
            Permission denied when talking to the database. In Firebase Console → Firestore → Rules, publish rules that allow this app’s collections—including `offers` for negotiated offers alongside `investments`. From the project root you can run: npm run firebase -- deploy --only firestore:rules
            """
        case 14: // UNAVAILABLE
            return "The database could not be reached. Check your internet connection and try again."
        case 8: // RESOURCE_EXHAUSTED
            return "The database is busy or over quota. Wait a moment and try again."
        case 4: // DEADLINE_EXCEEDED
            return "The request timed out. Check your connection and try again."
        default:
            let base = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty {
                return "A database error occurred (code \(ns.code))."
            }
            return base
        }
    }
}
