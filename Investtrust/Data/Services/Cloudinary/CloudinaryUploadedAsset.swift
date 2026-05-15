import Foundation

// Result of a successful Cloudinary upload — the delivery URL is stored on the opportunity,
// and the publicId is kept for later deletion when the seeker removes the listing
struct CloudinaryUploadedAsset {
    let secureURL: String
    let publicId: String?
}
