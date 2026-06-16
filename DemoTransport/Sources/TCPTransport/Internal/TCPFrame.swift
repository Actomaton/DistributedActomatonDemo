/// One framed message on a connection. The transport is **bidirectional**: either side may send an
/// `invocation` (and await a `reply`), so a server can push to a subscribed client over the same
/// connection the client dialed. `hello` announces the sender's `nodeID` so each side can route calls
/// back by node.
enum TCPFrame: Codable, Sendable
{
    case hello(nodeID: String)
    case invocation(TCPInvocationEnvelope)
    case reply(TCPReplyEnvelope)
}
