import Foundation

public enum BonjourActorSystemError: Error, CustomStringConvertible
{
    case actorNotFound(BonjourActorID)
    case peerNotConnected(UUID)
    case notSupported(String)
    case decodingFailure(String)
    case remote(String)

    public var description: String
    {
        switch self {
        case .actorNotFound(let id): return "Actor not found: \(id)"
        case .peerNotConnected(let id): return "Peer not connected: \(id)"
        case .notSupported(let s): return "Not supported: \(s)"
        case .decodingFailure(let s): return "Decoding failure: \(s)"
        case .remote(let s): return "Remote error: \(s)"
        }
    }
}
