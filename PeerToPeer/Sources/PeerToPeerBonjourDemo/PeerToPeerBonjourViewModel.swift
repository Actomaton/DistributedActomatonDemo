import BonjourTransport
import DistributedActomaton
import Observation
import PeerToPeerSwiftUI

/// Bonjour bootstrap: this process is exactly **one** peer node. It starts a `BonjourActorSystem`
/// (Bonjour discovery + TCP), then wires the mesh *reactively* — every time the discovered peer set
/// changes, it re-sends `.connect(peers:)` with the current peer IDs. Launch the app on two or more
/// machines (or as two processes) and they find each other on the local network.
///
/// Contrast with the InMemory app, which knows all peer IDs synchronously and wires the mesh once.
@MainActor
@Observable
final class PeerToPeerBonjourViewModel
{
    let peer: PeerViewModel<BonjourActorSystem>

    /// Discovered peers, mirrored for the UI.
    private(set) var discoveredPeers: [BonjourActorSystem.PeerInfo] = []

    let nickname: String

    private let system: BonjourActorSystem
    private var started = false

    init(nickname: String)
    {
        self.nickname = nickname

        let system = BonjourActorSystem(nickname: nickname)
        self.system = system

        let (stream, continuation) = AsyncStream.makeStream(of: ChatState<BonjourActorID>.self)
        let env = ChatEnv(system: system, publish: {
            continuation.yield($0)
        })
        let actor = ChatPeerActomaton<BonjourActorSystem>(
            state: ChatState(name: nickname),
            reducer: makeChatReducer(),
            environment: env,
            actorSystem: system
        )
        self.peer = PeerViewModel(name: nickname, peer: actor, updates: stream)
    }

    func start() async
    {
        guard !started else { return }
        started = true

        Task {
            await peer.observe()
        }

        do {
            try system.start()
        }
        catch {
            print("[PeerToPeerBonjour] failed to start: \(error)")
            return
        }

        // React to discovery: each change re-sends the full current peer set to the local reducer.
        _ = system.observePeers { [weak self] infos in
            Task { @MainActor in
                self?.handleDiscoveredPeers(infos)
            }
        }
    }

    private func handleDiscoveredPeers(_ infos: [BonjourActorSystem.PeerInfo])
    {
        discoveredPeers = infos.sorted {
            $0.nickname < $1.nickname
        }
        let ids = system.currentPeerIDs()
        Task {
            await peer.connect(to: ids)
        }
    }
}
