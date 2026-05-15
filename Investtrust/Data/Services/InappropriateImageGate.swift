import Foundation
import NSFWDetector
import UIKit

// Runs on-device content screening before a photo is uploaded to Cloudinary.
// Blocks uploads when the NSFW confidence score is above the threshold.
enum InappropriateImageGate {
    static var nsfwThreshold: Float = 0.85  // 85% confidence required to block the upload

    enum GateError: LocalizedError {
        case inappropriateContent
        case detectionFailed(String)

        var errorDescription: String? {
            switch self {
            case .inappropriateContent:
                return "This image can’t be uploaded. Please choose a different photo."
            case .detectionFailed(let message):
                return message
            }
        }
    }

    // Throws GateError.inappropriateContent if the image fails the NSFW check
    static func validateForUpload(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var didResume = false
            func resumeOnce(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                body()
            }

            NSFWDetector.shared.check(image: image) { result in
                resumeOnce {
                    switch result {
                    case .success(let nsfwConfidence):
                        if nsfwConfidence >= Self.nsfwThreshold {
                            cont.resume(throwing: GateError.inappropriateContent)
                        } else {
                            cont.resume()
                        }
                    case .error(let error):
                        // Fail open when the model can't produce an NSFW score (e.g. unusual image scale/orientation)
                        let text = error.localizedDescription
                            + " "
                            + (error as NSError).domain
                        if text.contains("No NSFW Observation") {
                            cont.resume()
                        } else {
                            cont.resume(throwing: GateError.detectionFailed(error.localizedDescription))
                        }
                    }
                }
            }
        }
    }

    // Convenience wrapper — decodes raw image data and runs the same NSFW check
    static func validateImageDataForUpload(_ data: Data) async throws {
        guard let image = UIImage(data: data) else { return }
        try await validateForUpload(image)
    }
}
