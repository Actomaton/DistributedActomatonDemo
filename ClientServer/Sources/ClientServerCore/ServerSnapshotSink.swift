import Distributed
import DistributedActomaton
import Foundation

// Transport-agnostic client-server logic. This library depends ONLY on `DistributedActomaton`,
// never on a concrete actor system. Each app target binds `InMemoryActorSystem` or
// `BonjourActorSystem`.

// This file is the contract shared by the server and client actomatons: the snapshot payload the
// server pushes, and the `@Resolvable` sink it pushes through.

// MARK: - Server → client push payload

/// The snapshot the server broadcasts to every subscriber. It is *also* the clients' `Action`
/// type: each client is a full `DistributedActomaton` whose reducer simply absorbs the latest
/// snapshot. The server names only this type when pushing — never any client's `State`.
public struct ServerSnapshot: Codable, Equatable, Sendable
{
    public var count: Int
    public var events: [ServerEvent]

    public init(count: Int = 0, events: [ServerEvent] = [])
    {
        self.count = count
        self.events = events
    }
}

public struct ServerEvent: Codable, Equatable, Sendable, Identifiable
{
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String)
    {
        self.id = id
        self.text = text
    }
}

// MARK: - @Resolvable type-erased sink (concrete `Action`)

/// A concrete-`Action` `@Resolvable` protocol: its method takes a `ServerSnapshot`, *not* an
/// associated type, so it resolves and calls over the wire (the associated-type form aborts at
/// runtime — see `DistributedResolvableLimitationTests`). The server resolves `any ServerSnapshotSink`,
/// naming only `ServerSnapshot`, and stays decoupled from each client's private `State`.
@Resolvable
public protocol ServerSnapshotSink: DistributedActor where ActorSystem: DistributedActorSystem<any Codable>
{
    distributed func send(_ snapshot: ServerSnapshot, id: DistributedSendID?)
}

// Any `DistributedActomaton` whose `Action` is `ServerSnapshot` is a `ServerSnapshotSink`. The
// conditional conformance constrains only `Action`, so the receiver keeps its own `State`.
extension DistributedActomaton: ServerSnapshotSink where Action == ServerSnapshot {}
