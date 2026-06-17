import BonjourTransport
import Foundation
import TCPTransport
import XCTest

final class DemoTransportTests: XCTestCase
{
    func testTCPActorIDDescriptionAndCodableRoundTrip() throws
    {
        let actorID = TCPActorID(nodeID: "server", name: "actomaton")

        XCTAssertEqual(actorID.description, "actomaton@server")
        XCTAssertEqual(try roundTrip(actorID), actorID)
    }

    func testBonjourActorIDDescriptionAndCodableRoundTrip() throws
    {
        let uuid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let actorID = BonjourActorID(nodeID: uuid, name: "actomaton")

        XCTAssertEqual(actorID.description, "actomaton@11111111")
        XCTAssertEqual(try roundTrip(actorID), actorID)
    }

    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value
    {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
