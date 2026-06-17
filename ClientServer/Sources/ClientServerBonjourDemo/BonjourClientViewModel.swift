import BonjourTransport
import ClientServerSwiftUI
import DistributedActomaton
import Foundation
import Observation

/// Bonjour client node: starts discovery, waits to find the server (by ``serverNickname``), resolves
/// a remote proxy to it, then builds a `ClientViewModel` and subscribes. The `ClientViewModel` only
/// exists once the server is found — until then the UI shows a "searching" state.
@MainActor
@Observable
final class BonjourClientViewModel
{
    let nickname: String

    private(set) var client: ClientViewModel<BonjourActorSystem>?
    private(set) var discoveredPeers: [BonjourActorSystem.PeerInfo] = []

    private let system: BonjourActorSystem
    private let receiver: ClientActomaton<BonjourActorSystem>
    private let snapshotStream: AsyncStream<ServerSnapshot>
    private var started = false

    init(nickname: String)
    {
        self.nickname = nickname

        let system = BonjourActorSystem(nickname: nickname)
        self.system = system

        let (stream, continuation) = AsyncStream.makeStream(of: ServerSnapshot.self)
        self.snapshotStream = stream
        self.receiver = ClientActomaton<BonjourActorSystem>(
            state: ClientState(),
            reducer: clientReducer,
            environment: ClientEnv(publish: {
                continuation.yield($0)
            }),
            actorSystem: system
        )
    }

    func start() async
    {
        guard !started else { return }
        started = true

        do {
            try system.start()
        }
        catch {
            print("[ClientServerBonjour] client failed to start: \(error)")
            return
        }

        _ = system.observePeers { [weak self] infos in
            Task { @MainActor in
                self?.handleDiscoveredPeers(infos)
            }
        }
    }

    private func handleDiscoveredPeers(_ infos: [BonjourActorSystem.PeerInfo])
    {
        discoveredPeers = infos

        // Bind to the server exactly once, as soon as it appears.
        let serverInfo = infos.first(where: {
            $0.nickname == serverNickname
        })
        guard client == nil, let serverInfo else { return }

        // The server hosts its singleton actor under the same well-known name as every node.
        let serverID = BonjourActorID(nodeID: serverInfo.nodeID, name: system.actorName)
        guard let proxy = try? ServerActomaton<BonjourActorSystem>.resolve(id: serverID, using: system) else {
            return
        }

        let vm = ClientViewModel(
            name: nickname,
            server: proxy,
            receiver: receiver,
            updates: snapshotStream
        )
        self.client = vm

        Task {
            await vm.observe()
        }
        Task {
            await vm.subscribe()
        }
    }
}
