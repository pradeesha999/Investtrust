import Foundation

/// Unsigned video upload to Cloudinary (same preset as images — enable **video** in that upload preset in the Cloudinary console).
enum CloudinaryVideoUploadClient {
    enum UploadError: LocalizedError {
        case invalidResponse
        case httpStatus(Int, String?)
        case missingSecureURL

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from video upload."
            case .httpStatus(let code, let body):
                if let body, !body.isEmpty {
                    return "Video upload failed (HTTP \(code)): \(body)"
                }
                return "Video upload failed (HTTP \(code)). Enable unsigned video uploads for your preset in Cloudinary."
            case .missingSecureURL:
                return "Video upload did not return a URL."
            }
        }
    }

    private struct UploadResponse: Decodable {
        let secure_url: String?
        let public_id: String?
        let error: CloudinaryAPIError?
    }

    private struct CloudinaryAPIError: Decodable {
        let message: String?
    }

    /// Uploads video bytes; returns delivery URL and optional `public_id` (for deletes).
    static func uploadVideoData(_ data: Data, filename: String = "video.mp4") async throws -> CloudinaryUploadedAsset {
        let cloud = CloudinaryConfig.cloudName
        let preset = CloudinaryConfig.uploadPreset
        guard let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloud)/video/upload") else {
            throw UploadError.invalidResponse
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField(name: "upload_preset", value: preset)

        let lower = filename.lowercased()
        let mime: String
        if lower.hasSuffix(".mov") {
            mime = "video/quicktime"
        } else if lower.hasSuffix(".m4v") {
            mime = "video/x-m4v"
        } else {
            mime = "video/mp4"
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let disposition = "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
        body.append(disposition.data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 600

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: respData, encoding: .utf8).map { String($0.prefix(500)) }
            throw UploadError.httpStatus(http.statusCode, snippet)
        }

        let decoded = try JSONDecoder().decode(UploadResponse.self, from: respData)
        if let apiErr = decoded.error?.message, !apiErr.isEmpty {
            throw UploadError.httpStatus(http.statusCode, apiErr)
        }
        guard let secure = decoded.secure_url?.trimmingCharacters(in: .whitespacesAndNewlines), !secure.isEmpty else {
            throw UploadError.missingSecureURL
        }
        let pid = decoded.public_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CloudinaryUploadedAsset(secureURL: secure, publicId: (pid?.isEmpty == false) ? pid : nil)
    }
}
