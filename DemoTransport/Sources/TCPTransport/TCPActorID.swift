import Foundation

/// Actor ID for ``TCPActorSystem``: a node name plus a per-node actor name. A node hosts a single
/// well-known actor (name `"actomaton"`), so a peer can address it from just the node name.
public struct TCPActorID: Hashable, Sendable, Codable, CustomStringConvertible
{
    public let nodeID: String
    public let name: String

    public init(nodeID: String, name: String)
    {
        self.nodeID = nodeID
        self.name = name
    }

    public var description: String
    {
        "\(name)@\(nodeID)"
    }
}
