import ClientServerCore
import Foundation
import XCTest

final class ClientServerCoreTests: XCTestCase
{
    func testServerStateSnapshotOmitsSubscriberIDs()
    {
        let event = ServerEvent(text: "client +5 -> 5")
        let state = ServerState<String>(
            count: 5,
            events: [event],
            subscriberIDs: ["client"]
        )

        XCTAssertEqual(state.snapshot.count, 5)
        XCTAssertEqual(state.snapshot.events, [event])
    }

    func testServerActionCodableRoundTrip() throws
    {
        let action = ServerAction<String>.increment(by: 3, who: "client")
        let decoded = try roundTrip(action)

        guard case let .increment(by, who) = decoded else {
            XCTFail("Expected increment action")
            return
        }

        XCTAssertEqual(by, 3)
        XCTAssertEqual(who, "client")
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value
    {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
