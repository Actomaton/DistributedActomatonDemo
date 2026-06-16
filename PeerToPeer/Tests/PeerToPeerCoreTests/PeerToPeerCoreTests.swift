import Foundation
import PeerToPeerCore
import XCTest

final class PeerToPeerCoreTests: XCTestCase
{
    func testChatMessageStoresSenderAndText()
    {
        let message = ChatMessage(sender: "alice", text: "hello")

        XCTAssertEqual(message.sender, "alice")
        XCTAssertEqual(message.text, "hello")
    }

    func testChatActionCodableRoundTrip() throws
    {
        let action = ChatAction<String>.deliver(sender: "bob", text: "hi")
        let decoded = try roundTrip(action)

        guard case let .deliver(sender, text) = decoded else {
            XCTFail("Expected deliver action")
            return
        }

        XCTAssertEqual(sender, "bob")
        XCTAssertEqual(text, "hi")
    }

    func testChatStateStartsWithPeerIDsAndLog()
    {
        let message = ChatMessage(sender: "alice", text: "hello")
        let state = ChatState(name: "alice", peerIDs: ["bob"], log: [message])

        XCTAssertEqual(state.name, "alice")
        XCTAssertEqual(state.peerIDs, ["bob"])
        XCTAssertEqual(state.log, [message])
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value
    {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
