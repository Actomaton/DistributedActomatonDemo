import Distributed
import DistributedActomaton
import Foundation
import Observation
import PeerToPeerCore

/// One peer's view-facing state: a live mirror of the actomaton's `ChatState` plus the text being
/// typed. Generic over the actor system, so the InMemory and Bonjour apps share it unchanged.
/// Mutations happen on the main actor as snapshots arrive on the `updates` stream.
@MainActor
@Observable
public final class PeerViewModel<System: DistributedActorSystem<any Codable>>: Identifiable
    where System.ActorID: Codable & Sendable & Hashable
{
    public let name: String
    public var state: ChatState<System.ActorID>
    public var draft: String = ""

    public nonisolated var id: String { name }

    private let peer: ChatPeerActomaton<System>
    private let updates: AsyncStream<ChatState<System.ActorID>>

    /// The underlying actomaton's distributed `ActorID`, used to wire up the peer mesh.
    public nonisolated var actorID: System.ActorID { peer.id }

    public init(
        name: String,
        peer: ChatPeerActomaton<System>,
        updates: AsyncStream<ChatState<System.ActorID>>
    )
    {
        self.name = name
        self.peer = peer
        self.updates = updates
        self.state = ChatState(name: name)
    }

    public func observe() async
    {
        for await state in updates {
            self.state = state
        }
    }

    public func connect(to peers: [System.ActorID]) async
    {
        try? await peer.send(.connect(peers: peers))
    }

    public func post()
    {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""

        Task {
            try? await peer.send(.post(text))
        }
    }
}
