import Foundation

// Ported from the `DistributedChatPoC` Bonjour PoC, adapted for the Actomaton demos:
// renamed `ChatActorID` → `BonjourActorID` and made the wire types demo-neutral.

/// Actor ID for ``BonjourActorSystem``: the hosting node's UUID plus a per-node actor name.
public struct BonjourActorID: Hashable, Sendable, Codable, CustomStringConvertible
{
    public let nodeID: UUID
    public let name: String

    public init(nodeID: UUID, name: String)
    {
        self.nodeID = nodeID
        self.name = name
    }

    public var description: String
    {
        "\(name)@\(nodeID.uuidString.prefix(8))"
    }
}
