import Distributed
import Foundation

public final class TCPResultHandler: DistributedTargetInvocationResultHandler, @unchecked Sendable
{
    public typealias SerializationRequirement = any Codable

    private let callID: UUID
    private let lock = NSLock()
    private var reply: TCPReplyEnvelope?

    init(callID: UUID)
    {
        self.callID = callID
    }

    func takeReply() -> TCPReplyEnvelope?
    {
        lock.withLock { reply }
    }

    public func onReturn<Success: Codable>(value: Success) async throws
    {
        let payload = try JSONEncoder().encode(value)
        lock.withLock {
            reply = TCPReplyEnvelope(callID: callID, payload: payload, errorMessage: nil)
        }
    }

    public func onReturnVoid() async throws
    {
        lock.withLock {
            reply = TCPReplyEnvelope(callID: callID, payload: nil, errorMessage: nil)
        }
    }

    public func onThrow<Err: Error>(error: Err) async throws
    {
        lock.withLock {
            reply = TCPReplyEnvelope(callID: callID, payload: nil, errorMessage: "\(error)")
        }
    }
}
