import Foundation

struct TCPReplyEnvelope: Codable, Sendable
{
    let callID: UUID
    let payload: Data?
    let errorMessage: String?
}
