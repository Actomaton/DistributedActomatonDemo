import Foundation

struct BonjourReplyEnvelope: Codable, Sendable
{
    var callID: UUID
    var payload: Data?
    var errorMessage: String?
}
