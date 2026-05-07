import FirebaseStorage
import Foundation

/// Maps Firebase Storage `NSError`s to short, actionable copy. Raw messages often look like
/// `Object investments/…/signatures/….png` which is confusing in the UI.
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

    /// Firebase often formats failures as `Object investments/…` (**no** leading slash before `investments`).
    private static func isRawFirebaseStorageObjectLine(_ s: String) -> Bool {
        s.hasPrefix("Object ") && s.contains("investments/")
    }

    private static let genericStorageUploadHint =
        "Could not upload to Firebase Storage under investments/{investmentId}/... (for signatures/MOA/proofs). Check your network, sign in again, and deploy Storage rules that allow authenticated writes there."
}
