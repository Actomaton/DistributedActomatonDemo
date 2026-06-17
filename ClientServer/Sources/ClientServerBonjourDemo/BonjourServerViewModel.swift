import BonjourTransport
import ClientServerSwiftUI
import DistributedActomaton
import Foundation
import Observation

/// The well-known nickname the server advertises so clients can pick it out of Bonjour discovery.
let serverNickname = "server"

/// Bonjour server node: hosts the authoritative `ServerActomaton` and waits. Clients discover it by
/// nickname, subscribe, and the server's effects push snapshots back to each subscriber's sink.
@MainActor
@Observable
final class BonjourServerViewModel
{
    let server: ServerViewModel<BonjourActorSystem>

    private let system: BonjourActorSystem
    private let serverActor: ServerActomaton<BonjourActorSystem>
    private var started = false

    init()
    {
        let system = BonjourActorSystem(nickname: serverNickname)
        self.system = system

        let (stream, continuation) = AsyncStream.makeStream(of: ServerState<BonjourActorID>.self)
        let env = ServerEnv(system: system, publish: {
            continuation.yield($0)
        })
        let actor = ServerActomaton<BonjourActorSystem>(
            state: ServerState(),
            reducer: makeServerReducer(),
            environment: env,
            actorSystem: system
        )
        self.serverActor = actor
        self.server = ServerViewModel(updates: stream)
    }

    func start() async
    {
        guard !started else { return }
        started = true

        Task {
            await server.observe()
        }

        do {
            try system.start()
        }
        catch {
            print("[ClientServerBonjour] server failed to start: \(error)")
        }
    }
}
