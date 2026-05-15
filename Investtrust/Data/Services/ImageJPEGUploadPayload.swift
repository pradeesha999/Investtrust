import Foundation
import UIKit

// Converts picker/camera image data to JPEG before uploading to Cloudinary
enum ImageJPEGUploadPayload {
    static func jpegForUpload(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.88) ?? data
    }
}
