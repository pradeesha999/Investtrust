import Foundation
import NSFWDetector
import UIKit

/// On-device NSFW screening before uploads (lovoo `NSFWDetector`). Assistive only; may false-positive/negative.
enum InappropriateImageGate {
    /// Confidence at or above this blocks upload (0...1).
    static var nsfwThreshold: Float = 0.85

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

    /// Throws if the image is likely inappropriate for the marketplace.
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
                        // Vision/CoreML may omit the expected "NSFW" observation (orientation, scale, model output).
                        // Fail open for that case so uploads work; lovoo's callback can also fire more than once — never resume twice.
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

    /// Validates `Data` as JPEG/PNG bitmap; skips gate if decoding fails (caller should validate separately).
    static func validateImageDataForUpload(_ data: Data) async throws {
        guard let image = UIImage(data: data) else { return }
        try await validateForUpload(image)
    }
}
