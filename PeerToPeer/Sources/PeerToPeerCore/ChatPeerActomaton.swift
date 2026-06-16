import Distributed
import DistributedActomaton
import Foundation

// Transport-agnostic peer-to-peer chat logic. This library depends ONLY on `DistributedActomaton`
// (the generic, transport-neutral core) — never on `InMemoryActorSystem` or `BonjourActorSystem`.
// Each app target binds a concrete `DistributedActorSystem`; the dependency split is the proof that
// the reducer is transport-agnostic.

// NOTE: Every type that crosses the wire is top-level (non-nested). The payload types are *generic*
// over the actor system's `ActorID`, so the wire substitution becomes a bound generic such as
// `ChatAction<InMemoryActorID>` / `ChatAction<BonjourActorID>`.

// MARK: - Action / State (generic over the actor system's `ActorID`)

public enum ChatAction<ID: Codable & Sendable & Hashable>: Codable, Sendable
{
    /// Register the IDs of the *other* peers in the mesh.
    case connect(peers: [ID])

    /// The local user posts a message from this peer.
    case post(String)

    /// A "reverse letter" delivered from another peer's effect over the wire.
    case deliver(sender: String, text: String)
}

public struct ChatMessage: Codable, Equatable, Sendable, Identifiable
{
    public var id: UUID
    public var sender: String
    public var text: String

    public init(id: UUID = UUID(), sender: String, text: String)
    {
        self.id = id
        self.sender = sender
        self.text = text
    }
}

public struct ChatState<ID: Codable & Sendable & Hashable>: Codable, Equatable, Sendable
{
    public var name: String
    public var peerIDs: [ID]
    public var log: [ChatMessage]

    public init(name: String, peerIDs: [ID] = [], log: [ChatMessage] = [])
    {
        self.name = name
        self.peerIDs = peerIDs
        self.log = log
    }
}

// MARK: - Environment

/// Local-only (never crosses the wire): carries this peer's own actor system so effects can resolve
/// remote peers, plus a `publish` sink that mirrors committed state into the SwiftUI view model.
public struct ChatEnv<System: DistributedActorSystem<any Codable>>: Sendable
    where System.ActorID: Codable & Sendable & Hashable
{
    public let system: System
    public let publish: @Sendable (ChatState<System.ActorID>) -> Void

    public init(system: System, publish: @escaping @Sendable (ChatState<System.ActorID>) -> Void)
    {
        self.system = system
        self.publish = publish
    }
}

// MARK: - Actomaton (generic over an arbitrary `DistributedActorSystem`)

public typealias ChatPeerActomaton<System: DistributedActorSystem<any Codable>> =
    DistributedActomaton<ChatAction<System.ActorID>, ChatState<System.ActorID>, Never, System>
    where System.ActorID: Codable & Sendable & Hashable

/// Serializes the UI-mirroring effects in submission order (`.runOldest(maxCount: 1, .suspendNew)`),
/// so committed state snapshots reach the view model in the exact order the reducer produced them —
/// even under rapid input, where otherwise-concurrent effect tasks could publish out of order.
private struct PublishQueue: Oldest1SuspendNewEffectQueue {}

/// Builds the chat reducer for *any* actor system whose `ActorID` is `Codable`. The logic is
/// identical regardless of transport; only the `ActorID` type varies.
public func makeChatReducer<System: DistributedActorSystem<any Codable>>()
    -> Reducer<ChatAction<System.ActorID>, ChatState<System.ActorID>, ChatEnv<System>, Never>
    where System.ActorID: Codable & Sendable & Hashable
{
    // The reducer body only mutates state; *all* side effects (publishing to the view model and
    // sending over the wire) happen inside the returned `Effect`.
    Reducer { action, state, env in
        switch action {
        case let .connect(peers):
            state.peerIDs = peers
            return publish(state, env)

        case let .post(text):
            // Echo locally, then fan the message out to every other peer as a `.deliver` reverse letter.
            state.log.append(ChatMessage(sender: state.name, text: text))

            let snapshot = state
            let peers = state.peerIDs
            let sender = state.name

            return Effect.fireAndForget(queue: PublishQueue()) { _ in
                env.publish(snapshot)

                // Parallel fan-out: peers are independent, so one unreachable peer must not delay or
                // abort delivery to the others (each send isolated with `try?`). The group awaits every
                // send, so this post's effect still completes ahead of the next on the serial queue.
                await withTaskGroup(of: Void.self) { group in
                    for peerID in peers {
                        group.addTask {
                            // Each `resolve` yields a *remote* proxy, so `send` round-trips over the wire.
                            let peer = try? ChatPeerActomaton<System>.resolve(id: peerID, using: env.system)
                            try? await peer?.send(.deliver(sender: sender, text: text))
                        }
                    }
                }
            }

        case let .deliver(sender, text):
            state.log.append(ChatMessage(sender: sender, text: text))
            return publish(state, env)
        }
    }
}

/// Mirrors `state` into the view model from inside an `Effect`, on the serial ``PublishQueue``.
private func publish<System: DistributedActorSystem<any Codable>>(
    _ state: ChatState<System.ActorID>,
    _ env: ChatEnv<System>
) -> Effect<ChatAction<System.ActorID>, Never>
    where System.ActorID: Codable & Sendable & Hashable
{
    .fireAndForget(queue: PublishQueue()) { _ in
        env.publish(state)
    }
}
