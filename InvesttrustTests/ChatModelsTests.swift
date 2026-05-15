import XCTest
@testable import Investtrust

// Tests for the chat thread model.
// counterpartyId drives the "Contact seeker / investor" button and the chat list avatars.
final class ChatModelsTests: XCTestCase {

    private func makeThread(
        id: String = "thread-1",
        seekerId: String? = "seeker-1",
        investorId: String? = "investor-1"
    ) -> ChatThread {
        ChatThread(
            id: id,
            seekerId: seekerId,
            investorId: investorId,
            title: "Retail expansion",
            lastMessagePreview: "Hi",
            lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testCounterpartyId_returnsOtherPartyForSeekerOrInvestor() {
        // Each side of the chat should see the other person as their counterparty
        let thread = makeThread()
        XCTAssertEqual(thread.counterpartyId(currentUserId: "seeker-1"), "investor-1")
        XCTAssertEqual(thread.counterpartyId(currentUserId: "investor-1"), "seeker-1")
    }

    func testCounterpartyId_isNilWhenCurrentUserIdMissing() {
        // If the session hasn't loaded yet, no counterparty should be resolved
        let thread = makeThread()
        XCTAssertNil(thread.counterpartyId(currentUserId: nil))
    }

    func testCounterpartyId_fallsBackWhenCurrentUserIdNotPresentInThread() {
        // A user viewing someone else's thread falls back to the investor side
        let thread = makeThread()
        XCTAssertEqual(thread.counterpartyId(currentUserId: "stranger"), "investor-1")
    }
}
