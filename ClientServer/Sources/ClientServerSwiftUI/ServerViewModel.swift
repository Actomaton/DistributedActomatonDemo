import ClientServerCore
import Distributed
import DistributedActomaton
import Observation
import SwiftUI
import SwiftUIDemoSupport

/// Mirrors the authoritative server state into the server panel. Generic over the actor system, so
/// both apps reuse it.
@MainActor
@Observable
public final class ServerViewModel<System: DistributedActorSystem<any Codable>>
    where System.ActorID: Codable & Sendable & Hashable
{
    public var state: ServerState<System.ActorID>

    private let updates: AsyncStream<ServerState<System.ActorID>>

    public init(updates: AsyncStream<ServerState<System.ActorID>>)
    {
        self.updates = updates
        self.state = ServerState()
    }

    public func observe() async
    {
        for await state in updates {
            self.state = state
        }
    }
}

public struct ServerPanel<System: DistributedActorSystem<any Codable>>: View
    where System.ActorID: Codable & Sendable & Hashable
{
    private let server: ServerViewModel<System>

    public init(server: ServerViewModel<System>)
    {
        self.server = server
    }

    public var body: some View
    {
        DemoCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Server", systemImage: "server.rack").font(.headline)

                Text("\(server.state.count)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: server.state.count)

                Divider()
                Text("Activity").font(.caption).foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(server.state.events) { event in
                                Text(event.text)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id(scrollAnchor)
                        }
                    }
                    .onChange(of: server.state.events.count) {
                        withAnimation {
                            proxy.scrollTo(scrollAnchor, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private let scrollAnchor = "END"
}
