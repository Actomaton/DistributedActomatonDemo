import Distributed
import DistributedActomaton

// MARK: - Action / State (generic over the actor system's `ActorID`)

public enum ServerAction<ID: Codable & Sendable & Hashable>: Codable, Sendable
{
    /// A client registers its receiver actor's ID so the server can push snapshots back to it.
    case subscribe(clientID: ID)
    case increment(by: Int, who: String)
    case reset(who: String)
}

public struct ServerState<ID: Codable & Sendable & Hashable>: Codable, Equatable, Sendable
{
    public var count: Int
    public var events: [ServerEvent]

    /// Server-side bookkeeping; deliberately *not* part of `ServerSnapshot`, so subscriber IDs are
    /// never shipped to clients.
    public var subscriberIDs: [ID]

    public init(count: Int = 0, events: [ServerEvent] = [], subscriberIDs: [ID] = [])
    {
        self.count = count
        self.events = events
        self.subscriberIDs = subscriberIDs
    }

    mutating func log(_ text: String)
    {
        events.append(ServerEvent(text: text))

        if events.count > 12 {
            events.removeFirst(events.count - 12)
        }
    }

    public var snapshot: ServerSnapshot
    {
        ServerSnapshot(count: count, events: events)
    }
}

public struct ServerEnv<System: DistributedActorSystem<any Codable>>: Sendable
    where System.ActorID: Codable & Sendable & Hashable
{
    public let system: System
    public let publish: @Sendable (ServerState<System.ActorID>) -> Void

    public init(system: System, publish: @escaping @Sendable (ServerState<System.ActorID>) -> Void)
    {
        self.system = system
        self.publish = publish
    }
}

// MARK: - Actomaton (generic over an arbitrary `DistributedActorSystem`)

public typealias ServerActomaton<System: DistributedActorSystem<any Codable>> =
    DistributedActomaton<ServerAction<System.ActorID>, ServerState<System.ActorID>, Never, System>
    where System.ActorID: Codable & Sendable & Hashable

/// Serializes the server's publish-and-broadcast effects in submission order
/// (`.runOldest(maxCount: 1, .suspendNew)`). Each command's effect — push included — fully completes
/// before the next begins, so every client sees snapshots in the order the server committed them,
/// even under rapid clicks. The same queue type, reused in `clientReducer`, runs on each client's
/// own EffectManager, so the queues never interfere across actors.
struct PublishQueue: Oldest1SuspendNewEffectQueue {}

/// Builds the server reducer for *any* actor system whose `ActorID` is `Codable`. The logic is
/// identical regardless of transport; only the `ActorID` type varies.
public func makeServerReducer<System: DistributedActorSystem<any Codable>>()
    -> Reducer<ServerAction<System.ActorID>, ServerState<System.ActorID>, ServerEnv<System>, Never>
    where System.ActorID: Codable & Sendable & Hashable
{
    // The reducer body only mutates state; publishing and pushing over the wire happen inside the
    // returned `Effect`.
    Reducer { action, state, env in
        switch action {
        case let .subscribe(clientID):
            state.subscriberIDs.append(clientID)
            state.log("a client subscribed")

            let serverState = state
            let snapshot = state.snapshot

            return Effect.fireAndForget(queue: PublishQueue()) { _ in
                env.publish(serverState)

                // Push the current snapshot to the brand-new subscriber so its panel isn't blank.
                let sink = try $ServerSnapshotSink.resolve(id: clientID, using: env.system)
                try await sink.send(snapshot, id: nil)
            }

        case let .increment(by, who):
            state.count += by
            state.log("\(who) \(signed(by)) → \(state.count)")
            return broadcast(state, env)

        case let .reset(who):
            state.count = 0
            state.log("\(who) reset → 0")
            return broadcast(state, env)
        }
    }
}

private func signed(_ n: Int) -> String
{
    n >= 0 ? "+\(n)" : "\(n)"
}

/// Mirrors the new state into the server panel, then pushes the snapshot to *all* subscribers.
///
/// The fan-out is parallel (a `TaskGroup`), not a sequential `await` per subscriber: subscribers are
/// independent, so there's no reason a slow — or dead, via a thrown error — client should delay or
/// abort delivery to the others. Each push is isolated with `try?`, so one failure can't take down
/// the rest of the round.
///
/// Parallelism here does *not* fight the serial ``PublishQueue``: the queue orders broadcasts
/// *across* snapshots, while the `TaskGroup` parallelizes *within* one broadcast — orthogonal
/// concerns. The group awaits every child before the effect returns, so `broadcast(snap1)` still
/// finishes delivering to everyone before `broadcast(snap2)` starts; no client ever sees snapshots
/// out of order.
private func broadcast<System: DistributedActorSystem<any Codable>>(
    _ state: ServerState<System.ActorID>,
    _ env: ServerEnv<System>
) -> Effect<ServerAction<System.ActorID>, Never>
    where System.ActorID: Codable & Sendable & Hashable
{
    let serverState = state
    let snapshot = state.snapshot
    let subscriberIDs = state.subscriberIDs

    return Effect.fireAndForget(queue: PublishQueue()) { _ in
        env.publish(serverState)

        await withTaskGroup(of: Void.self) { group in
            for id in subscriberIDs {
                group.addTask {
                    let sink = try? $ServerSnapshotSink.resolve(id: id, using: env.system)
                    try? await sink?.send(snapshot, id: nil)
                }
            }
        }
    }
}
