import Foundation

struct BonjourInvocationEnvelope: Codable, Sendable
{
    var callID: UUID
    var target: BonjourActorID
    var method: String
    var genericSubs: [String]
    var arguments: [Data]
}
