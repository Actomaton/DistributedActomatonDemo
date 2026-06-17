import Distributed
import DistributedActomaton

// MARK: - State

/// The client's state is just the latest snapshot it has been pushed. Neither it, `ClientEnv`, nor
/// `clientReducer` references any `ActorID`, so the client side stays non-generic; only the
/// actomaton's `ActorSystem` varies.
public struct ClientState: Codable, Equatable, Sendable
{
    public var snapshot: ServerSnapshot

    public init(snapshot: ServerSnapshot = ServerSnapshot())
    {
        self.snapshot = snapshot
    }
}

public struct ClientEnv: Sendable
{
    public let publish: @Sendable (ServerSnapshot) -> Void

    public init(publish: @escaping @Sendable (ServerSnapshot) -> Void)
    {
        self.publish = publish
    }
}

// MARK: - Actomaton (generic over an arbitrary `DistributedActorSystem`)

/// The client receiver: a `DistributedActomaton` whose `Action` is `ServerSnapshot`, making it a
/// `ServerSnapshotSink` the server can push to (see `ServerSnapshotSink.swift`).
public typealias ClientActomaton<System: DistributedActorSystem<any Codable>> =
    DistributedActomaton<ServerSnapshot, ClientState, Never, System>

public let clientReducer = Reducer<ServerSnapshot, ClientState, ClientEnv, Never> { snapshot, state, env in
    state.snapshot = snapshot

    // `PublishQueue` is shared with the server reducer; on the client's own EffectManager it just
    // keeps successive snapshot publishes ordered.
    return .fireAndForget(queue: PublishQueue()) { _ in
        env.publish(snapshot)
    }
}
