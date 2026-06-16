import ClientServerSwiftUI
import DistributedActomatonTesting
import Observation

/// InMemory bootstrap: one server node and N client nodes on a shared in-process `InMemoryTransport`,
/// all in one process. Each client owns a `ClientActomaton` (the push target) and a *remote proxy* to
/// the server (the command target), resolved synchronously by the server's known ID.
@MainActor
@Observable
final class ClientServerInMemoryViewModel
{
    let server: ServerViewModel<InMemoryActorSystem>
    let clients: [ClientViewModel<InMemoryActorSystem>]

    // Retain the transport + server actomaton so the whole graph outlives the window.
    private let transport: InMemoryTransport
    private let serverActor: ServerActomaton<InMemoryActorSystem>

    private var started = false

    init(clientNames: [String])
    {
        let transport = InMemoryTransport()
        self.transport = transport

        let serverSystem = InMemoryActorSystem(nodeID: "server", transport: transport)
        let (serverStream, serverContinuation) = AsyncStream.makeStream(of: ServerState<InMemoryActorID>.self)

        let serverEnv = ServerEnv(
            system: serverSystem,
            publish: {
                serverContinuation.yield($0)
            }
        )

        let serverActor = ServerActomaton<InMemoryActorSystem>(
            state: ServerState(),
            reducer: makeServerReducer(),
            environment: serverEnv,
            actorSystem: serverSystem
        )
        self.serverActor = serverActor
        self.server = ServerViewModel(updates: serverStream)

        self.clients = clientNames.compactMap { name in
            let system = InMemoryActorSystem(nodeID: "client-\(name)", transport: transport)
            let (stream, continuation) = AsyncStream.makeStream(of: ServerSnapshot.self)
            let receiver = ClientActomaton<InMemoryActorSystem>(
                state: ClientState(),
                reducer: clientReducer,
                environment: ClientEnv(publish: {
                    continuation.yield($0)
                }),
                actorSystem: system
            )
            // Resolving the server from another node yields a true remote proxy.
            guard let serverProxy = try? ServerActomaton<InMemoryActorSystem>.resolve(id: serverActor.id, using: system) else {
                return nil
            }
            return ClientViewModel(name: name, server: serverProxy, receiver: receiver, updates: stream)
        }
    }

    func start() async
    {
        guard !started else { return }
        started = true

        Task {
            await server.observe()
        }

        for client in clients {
            Task {
                await client.observe()
            }
        }

        for client in clients {
            await client.subscribe()
        }
    }
}
