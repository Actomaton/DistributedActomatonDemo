import ClientServerCore
import Distributed
import DistributedActomaton
import Observation
import SwiftUI
import SwiftUIDemoSupport

/// One client: sends commands to the server over the wire and displays the snapshots the server
/// pushes back to its local receiver actor. Generic over the actor system.
@MainActor
@Observable
public final class ClientViewModel<System: DistributedActorSystem<any Codable>>: Identifiable
    where System.ActorID: Codable & Sendable & Hashable
{
    public let name: String
    public var snapshot = ServerSnapshot()

    public nonisolated var id: String { name }

    private let server: ServerActomaton<System>        // remote proxy to the server
    private let receiver: ClientActomaton<System>      // local sink the server pushes snapshots to
    private let updates: AsyncStream<ServerSnapshot>

    public init(
        name: String,
        server: ServerActomaton<System>,
        receiver: ClientActomaton<System>,
        updates: AsyncStream<ServerSnapshot>
    )
    {
        self.name = name
        self.server = server
        self.receiver = receiver
        self.updates = updates
    }

    public func observe() async
    {
        for await snapshot in updates {
            self.snapshot = snapshot
        }
    }

    public func subscribe() async
    {
        try? await server.send(.subscribe(clientID: receiver.id))
    }

    public func increment(_ by: Int)
    {
        Task {
            try? await server.send(.increment(by: by, who: name))
        }
    }

    public func reset()
    {
        Task {
            try? await server.send(.reset(who: name))
        }
    }
}

public struct ClientPanel<System: DistributedActorSystem<any Codable>>: View
    where System.ActorID: Codable & Sendable & Hashable
{
    private let client: ClientViewModel<System>

    public init(client: ClientViewModel<System>)
    {
        self.client = client
    }

    public var body: some View
    {
        DemoCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Dot(color: DemoPalette.color(for: client.name))
                        Text(client.name).font(.headline)
                    }
                    Text("sees count = \(client.snapshot.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: client.snapshot.count)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button("-1") {
                        client.increment(-1)
                    }
                    Button("+1") {
                        client.increment(1)
                    }
                    Button("+5") {
                        client.increment(5)
                    }
                    Button("Reset", role: .destructive) {
                        client.reset()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(height: 78)
    }
}
