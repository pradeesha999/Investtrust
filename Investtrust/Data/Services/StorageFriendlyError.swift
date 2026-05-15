import FirebaseStorage
import Foundation

// Converts raw Firebase Storage errors into readable messages for in-app alerts.
// Firebase's default messages include file paths that would confuse users.
enum StorageFriendlyError {
    static func userMessage(for error: Error) -> String {
        let ns = error as NSError
        // Same domain across SDK builds; include string fallback.
        let isStorageDomain = ns.domain == StorageErrorDomain
            || ns.domain == "FIRStorageErrorDomain"
        let diagnostics = " [\(ns.domain):\(ns.code)]"
        if isStorageDomain, let code = StorageErrorCode(rawValue: ns.code) {
            switch code {
            case .unauthenticated:
                return "Your session expired. Sign out and sign in again, then retry.\(diagnostics)"
            case .unauthorized:
                return "Upload was denied. On Firebase Console → Storage → Rules, ensure signed-in users can write under `investments/{investmentId}/…`, then publish rules.\(diagnostics)"
            case .quotaExceeded:
                return "Storage quota exceeded for this project. Try again later or upgrade the Firebase plan.\(diagnostics)"
            case .cancelled:
                return "Upload was cancelled.\(diagnostics)"
            case .retryLimitExceeded:
                return "Could not reach Firebase Storage after several tries. Check your network and try again.\(diagnostics)"
            default:
                break
            }
        }

        let desc = ns.localizedDescription
        if Self.isRawFirebaseStorageObjectLine(desc) {
            return Self.genericStorageUploadHint + diagnostics
        }
        return desc + diagnostics
    }

    // Detects raw Firebase Storage error messages that contain internal file paths
    private static func isRawFirebaseStorageObjectLine(_ s: String) -> Bool {
        s.hasPrefix("Object ") && s.contains("investments/")
    }

    private static let genericStorageUploadHint =
        "Could not upload to Firebase Storage under investments/{investmentId}/... (for signatures/MOA/proofs). Check your network, sign in again, and deploy Storage rules that allow authenticated writes there."
}
