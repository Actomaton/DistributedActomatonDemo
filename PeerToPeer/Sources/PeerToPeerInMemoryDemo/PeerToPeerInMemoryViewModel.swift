import DistributedActomatonTesting
import Observation
import PeerToPeerSwiftUI

/// InMemory bootstrap: builds the whole peer mesh in one process — one `InMemoryActorSystem` node
/// per peer, all sharing a single in-process `InMemoryTransport`, plus a `PeerViewModel` per peer.
///
/// Peer IDs are known *synchronously* here (`peer.actorID`), so the mesh is wired up directly at
/// `start()`. (The Bonjour app, by contrast, learns peer IDs asynchronously via discovery.)
@MainActor
@Observable
final class PeerToPeerInMemoryViewModel
{
    let peers: [PeerViewModel<InMemoryActorSystem>]

    private var started = false

    init(peerNames: [String])
    {
        let transport = InMemoryTransport()

        self.peers = peerNames.map { name in
            let system = InMemoryActorSystem(nodeID: "peer-\(name)", transport: transport)
            let (stream, continuation) = AsyncStream.makeStream(of: ChatState<InMemoryActorID>.self)
            let env = ChatEnv(system: system, publish: {
                continuation.yield($0)
            })
            let actor = ChatPeerActomaton<InMemoryActorSystem>(
                state: ChatState(name: name),
                reducer: makeChatReducer(),
                environment: env,
                actorSystem: system
            )
            return PeerViewModel(name: name, peer: actor, updates: stream)
        }
    }

    func start() async
    {
        guard !started else { return }
        started = true

        // Begin mirroring state into each view model.
        for peer in peers {
            Task {
                await peer.observe()
            }
        }

        // Tell every peer about the others (the full mesh minus itself).
        let ids = peers.map { $0.actorID }
        for index in peers.indices {
            let others = ids.enumerated()
                .filter {
                    $0.offset != index
                }
                .map { $0.element }
            await peers[index].connect(to: others)
        }
    }
}
