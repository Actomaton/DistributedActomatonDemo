import Foundation

struct BonjourHelloPayload: Codable, Sendable
{
    var nodeID: UUID
    var nickname: String
}
