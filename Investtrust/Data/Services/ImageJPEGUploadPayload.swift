import Foundation
import UIKit

/// Normalizes picker/camera bytes to JPEG for Cloudinary and consistent `image/jpeg` delivery.
enum ImageJPEGUploadPayload {
    static func jpegForUpload(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.88) ?? data
    }
}
