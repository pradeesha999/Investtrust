import XCTest
@testable import Investtrust

// Tests for the image moderation gate that blocks inappropriate uploads
// before they reach Cloudinary (shown as an inline error on the photo picker).
final class InappropriateImageGateTests: XCTestCase {
    func testGateErrorCopy() {
        // The user-facing error message must be non-empty so the alert has text to show
        let error = InappropriateImageGate.GateError.inappropriateContent
        XCTAssertFalse((error as LocalizedError).errorDescription?.isEmpty ?? true)
    }
}
