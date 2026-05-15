import XCTest
@testable import Investtrust

// Tests for the profile completeness check that gates an investor from sending a request.
// The app blocks "Invest" until every required field is filled in and the bio is long enough.
final class ProfileDetailsTests: XCTestCase {

    func testIsCompleteForInvesting_trueWhenAllRequiredFieldsArePresent() {
        // A fully filled-out profile should pass the completeness check
        let details = ProfileDetails(
            legalFullName: "Pat Lender",
            phoneNumber: "+94 11 555 0100",
            country: "Sri Lanka",
            city: "Colombo",
            shortBio: "Investor focused on small businesses.",
            experienceLevel: .intermediate
        )
        XCTAssertTrue(details.isCompleteForInvesting)
    }

    func testIsCompleteForInvesting_falseWhenAnyFieldIsMissing() {
        // Missing experience level — "Invest" button stays disabled
        var details = ProfileDetails(
            legalFullName: "Pat Lender",
            phoneNumber: "+94 11 555 0100",
            country: "Sri Lanka",
            city: "Colombo",
            shortBio: "Investor focused on small businesses.",
            experienceLevel: nil
        )
        XCTAssertFalse(details.isCompleteForInvesting)

        // Whitespace-only name — should be treated the same as an empty field
        details = ProfileDetails(
            legalFullName: "   ",
            phoneNumber: "+94 11 555 0100",
            country: "Sri Lanka",
            city: "Colombo",
            shortBio: "Investor focused on small businesses.",
            experienceLevel: .intermediate
        )
        XCTAssertFalse(details.isCompleteForInvesting)

        // Bio is too short — must be at least 12 characters
        details = ProfileDetails(
            legalFullName: "Pat Lender",
            phoneNumber: "+94 11 555 0100",
            country: "Sri Lanka",
            city: "Colombo",
            shortBio: "short",
            experienceLevel: .intermediate
        )
        XCTAssertFalse(details.isCompleteForInvesting)
    }

    func testMissingProfileHints_enumeratesExactlyTheMissingFields() {
        // The hint list drives the "Complete your profile" prompt shown before investing
        let details = ProfileDetails(
            legalFullName: "",
            phoneNumber: nil,
            country: "Sri Lanka",
            city: "Colombo",
            shortBio: "too short",
            experienceLevel: nil
        )
        let hints = details.missingProfileHints
        XCTAssertTrue(hints.contains("Legal full name"))
        XCTAssertTrue(hints.contains("Phone number"))
        XCTAssertFalse(hints.contains("Country"))
        XCTAssertFalse(hints.contains("City"))
        XCTAssertTrue(hints.contains("Short bio (at least 12 characters)"))
        XCTAssertTrue(hints.contains("Experience level"))
    }

    func testMissingProfileHints_emptyWhenComplete() {
        // A complete profile should produce no hints — the prompt should not appear
        let details = ProfileDetails(
            legalFullName: "Pat Lender",
            phoneNumber: "+94 11 555 0100",
            country: "Sri Lanka",
            city: "Colombo",
            shortBio: "Investor focused on small businesses.",
            experienceLevel: .experienced
        )
        XCTAssertTrue(details.missingProfileHints.isEmpty)
    }
}
