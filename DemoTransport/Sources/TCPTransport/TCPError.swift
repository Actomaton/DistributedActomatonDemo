public enum TCPError: Error, CustomStringConvertible
{
    case io(String)
    case connectionClosed
    case notConnected
    case actorNotFound(TCPActorID)
    case decoding(String)
    case remote(String)
    case unsupported(String)

    public var description: String
    {
        switch self {
        case let .io(s): return "I/O error: \(s)"
        case .connectionClosed: return "connection closed"
        case .notConnected: return "not connected (this node has no outbound connection)"
        case let .actorNotFound(id): return "actor not found: \(id)"
        case let .decoding(s): return "decoding failure: \(s)"
        case let .remote(s): return "remote error: \(s)"
        case let .unsupported(s): return "unsupported: \(s)"
        }
    }
}
