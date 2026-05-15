import CryptoKit
import Foundation

// Generates the HMAC-SHA256 signature required by Cloudinary's signed destroy API
enum CloudinarySignature {
    static func signParameters(_ params: [String: String], apiSecret: String) -> String {
        let sortedKeys = params.keys.sorted()
        let paramString = sortedKeys.map { "\($0)=\(params[$0]!)" }.joined(separator: "&")
        let stringToSign = paramString + apiSecret
        let digest = SHA256.hash(data: Data(stringToSign.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
