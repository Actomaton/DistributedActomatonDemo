import Foundation

extension BonjourActorSystem
{
    public struct PeerInfo: Hashable, Sendable, Identifiable
    {
        public var id: UUID { nodeID }
        public let nodeID: UUID
        public let nickname: String
    }
}
