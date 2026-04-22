import Foundation

/// Unsigned image upload to Cloudinary (`upload_preset` only — no API secret in the app).
enum CloudinaryImageUploadClient {
    enum UploadError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case missingSecureURL

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from image upload."
            case .httpStatus(let code):
                return "Image upload failed (HTTP \(code))."
            case .missingSecureURL:
                return "Image upload did not return a URL."
            }
        }
    }

    private struct UploadResponse: Decodable {
        let secure_url: String?
        let public_id: String?
    }

    /// Uploads image bytes; returns delivery URL and optional `public_id` (for deletes).
    /// - Parameter mimeType: Multipart `Content-Type` for the file part (e.g. `image/jpeg`, `image/png`).
    static func uploadImageData(
        _ data: Data,
        filename: String = "image.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> CloudinaryUploadedAsset {
        try await uploadData(
            data,
            filename: filename,
            mimeType: mimeType,
            resourceType: "image"
        )
    }

    /// Uploads any file type via Cloudinary `auto` resource detection (useful for PDFs/docs).
    static func uploadFileData(
        _ data: Data,
        filename: String,
        mimeType: String
    ) async throws -> CloudinaryUploadedAsset {
        try await uploadData(
            data,
            filename: filename,
            mimeType: mimeType,
            resourceType: "auto"
        )
    }

    private static func uploadData(
        _ data: Data,
        filename: String,
        mimeType: String,
        resourceType: String
    ) async throws -> CloudinaryUploadedAsset {
        let cloud = CloudinaryConfig.cloudName
        let preset = CloudinaryConfig.uploadPreset
        guard let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloud)/\(resourceType)/upload") else {
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

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let disposition = "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
        body.append(disposition.data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw UploadError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(UploadResponse.self, from: respData)
        guard let secure = decoded.secure_url?.trimmingCharacters(in: .whitespacesAndNewlines), !secure.isEmpty else {
            throw UploadError.missingSecureURL
        }
        let pid = decoded.public_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CloudinaryUploadedAsset(secureURL: secure, publicId: (pid?.isEmpty == false) ? pid : nil)
    }
}
