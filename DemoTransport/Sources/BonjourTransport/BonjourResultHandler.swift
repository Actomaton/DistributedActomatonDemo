import Distributed
import Foundation

public struct BonjourResultHandler: DistributedTargetInvocationResultHandler
{
    public typealias SerializationRequirement = any Codable

    let callID: UUID
    let peerNodeID: UUID
    let system: BonjourActorSystem

    public func onReturn<Success: Codable>(value: Success) async throws
    {
        let data = try JSONEncoder().encode(value)
        system.sendReply(
            BonjourReplyEnvelope(callID: callID, payload: data, errorMessage: nil),
            toNode: peerNodeID
        )
    }

    public func onReturnVoid() async throws
    {
        system.sendReply(
            BonjourReplyEnvelope(callID: callID, payload: nil, errorMessage: nil),
            toNode: peerNodeID
        )
    }

    public func onThrow<Err: Error>(error: Err) async throws
    {
        system.sendReply(
            BonjourReplyEnvelope(callID: callID, payload: nil, errorMessage: "\(error)"),
            toNode: peerNodeID
        )
    }
}
