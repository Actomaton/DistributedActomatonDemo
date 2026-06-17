import Foundation

struct TCPInvocationEnvelope: Codable, Sendable
{
    let callID: UUID
    let target: TCPActorID
    let method: String
    let genericSubs: [String]
    let arguments: [Data]
}
