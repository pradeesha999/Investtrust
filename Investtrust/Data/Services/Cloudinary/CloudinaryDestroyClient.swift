import Foundation

// Deletes images and videos from Cloudinary when the seeker removes an opportunity.
// Only works when API credentials are configured — otherwise the delete is silently skipped.
enum CloudinaryDestroyClient {
    private struct DestroyResponse: Decodable {
        let result: String?
        let error: CloudinaryAPIError?
    }

    private struct CloudinaryAPIError: Decodable {
        let message: String?
    }

    // Tries stored public IDs first; falls back to parsing IDs from delivery URLs for older listings
    static func deleteAssetsForOpportunity(
        imagePublicIds: [String],
        videoPublicId: String?,
        imageDeliveryURLs: [String],
        videoDeliveryURL: String?
    ) async {
        guard CloudinaryConfig.hasSignedApiCredentials,
              let apiKey = CloudinaryConfig.apiKey,
              let apiSecret = CloudinaryConfig.apiSecret
        else { return }

        var imageIds = Set(imagePublicIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        for url in imageDeliveryURLs {
            guard let pid = CloudinaryPublicIdExtractor.publicId(fromDeliveryURL: url) else { continue }
            imageIds.insert(pid)
        }

        var videoIds = Set<String>()
        if let v = videoPublicId?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            videoIds.insert(v)
        }
        if let v = videoDeliveryURL?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty,
           let pid = CloudinaryPublicIdExtractor.publicId(fromDeliveryURL: v),
           CloudinaryPublicIdExtractor.resourceFolder(fromDeliveryURL: v) == .video {
            videoIds.insert(pid)
        }

        for id in imageIds {
            try? await destroy(publicId: id, resource: "image", apiKey: apiKey, apiSecret: apiSecret)
        }
        for id in videoIds {
            try? await destroy(publicId: id, resource: "video", apiKey: apiKey, apiSecret: apiSecret)
        }
    }

    private static func destroy(publicId: String, resource: String, apiKey: String, apiSecret: String) async throws {
        let cloud = CloudinaryConfig.cloudName
        guard let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloud)/\(resource)/destroy") else { return }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let params: [String: String] = [
            "public_id": publicId,
            "signature_algorithm": "sha256",
            "timestamp": timestamp
        ]
        let signature = CloudinarySignature.signParameters(params, apiSecret: apiSecret)

        let pairs: [(String, String)] = [
            ("public_id", publicId),
            ("signature", signature),
            ("signature_algorithm", "sha256"),
            ("timestamp", timestamp),
            ("api_key", apiKey)
        ]
        let form = pairs.map { "\($0.0.formURLEncoded)=\($0.1.formURLEncoded)" }.joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.data(using: .utf8)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        if !(200 ... 299).contains(http.statusCode) {
            throw NSError(domain: "Investtrust", code: http.statusCode, userInfo: nil)
        }
        if let decoded = try? JSONDecoder().decode(DestroyResponse.self, from: data),
           let err = decoded.error?.message, !err.isEmpty {
            throw NSError(domain: "Investtrust", code: 400, userInfo: [NSLocalizedDescriptionKey: err])
        }
    }
}

private extension String {
    // RFC 3986-ish form encoding for Cloudinary POST bodies.
    var formURLEncoded: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
