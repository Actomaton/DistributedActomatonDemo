import Distributed
import Foundation

/// A portable, **bidirectional** `DistributedActorSystem` over plain TCP — POSIX sockets,
/// length-prefixed JSON frames, no Bonjour/mDNS. Built to run on macOS **and** Linux so the same
/// generic `DistributedActomaton` can be driven across an OS boundary.
///
/// ## Topology
///
/// A **server** node listens; **client** nodes dial it. After a `hello` handshake each side knows the
/// other's `nodeID`, so *either* side can make calls over the connection — i.e. the server can `send`
/// back to a client (the `@Resolvable ServerSnapshotSink` *push* path), not just reply to it. The
/// `ClientServerTCPDemo` itself uses the simpler **polling** path (the client reads `server.state`);
/// the push path is wired but reliably surfacing pushed snapshots on an idle CLI client hit a
/// Swift-concurrency scheduling issue.
///
/// Because a connection is bidirectional, the same primitives form a **peer mesh**: a `peer` node
/// listens *and* ``connect(host:port:)``s outward to the peers ordered after it, so each pair shares
/// exactly one connection over which both sides call. `PeerToPeerTCPDemo` drives that — every peer
/// owns its own `DistributedActomaton` and fans posts out to the others as `.deliver` reverse letters.
///
/// ## Generic substitutions
///
/// `recordGenericSubstitution` / `decodeGenericSubstitutions` round-trip via
/// `_mangledTypeName` / `_typeByName` (as `InMemoryActorSystem` and the Bonjour transport do).
/// `DistributedActomaton` is a generic actor, so every remote call records its generic arguments as
/// substitutions the callee must resolve — across the OS boundary, which is what this demo verifies.
public final class TCPActorSystem: DistributedActorSystem, @unchecked Sendable
{
    public typealias ActorID = TCPActorID
    public typealias SerializationRequirement = any Codable
    public typealias InvocationEncoder = TCPInvocationEncoder
    public typealias InvocationDecoder = TCPInvocationDecoder
    public typealias ResultHandler = TCPResultHandler

    public let nodeID: String

    private let lock = NSLock()
    private var localActors: [TCPActorID: any DistributedActor] = [:]
    private var pendingCalls: [UUID: CheckedContinuation<TCPReplyEnvelope, Error>] = [:]
    private var connections: [String: TCPConnection] = [:] // remote nodeID -> connection

    private init(nodeID: String)
    {
        self.nodeID = nodeID
        ignoreSIGPIPE()
    }

    /// Start a server node listening on `port`.
    public static func server(nodeID: String, port: UInt16) throws -> TCPActorSystem
    {
        let system = TCPActorSystem(nodeID: nodeID)
        try system.startListening(port: port)
        return system
    }

    /// Start a client node and dial `serverHost:serverPort`. Suspends until the `hello` handshake
    /// completes, so the first remote call doesn't race the connection setup.
    public static func client(nodeID: String, serverHost: String, serverPort: UInt16) async throws -> TCPActorSystem
    {
        let system = TCPActorSystem(nodeID: nodeID)
        let connection = try system.dial(host: serverHost, port: serverPort)
        try await connection.awaitHandshake(timeout: .seconds(3))
        return system
    }

    /// Start a **peer** node: listen on `port` so other peers can dial in. Unlike a `server`, a peer is
    /// also expected to ``connect(host:port:)`` outward to the peers ordered after it, forming a mesh
    /// where each pair shares one bidirectional connection (see `PeerToPeerTCPDemo`).
    public static func peer(nodeID: String, port: UInt16) throws -> TCPActorSystem
    {
        let system = TCPActorSystem(nodeID: nodeID)
        try system.startListening(port: port)
        return system
    }

    /// Dial another peer at `host:port` and suspend until its `hello` handshake completes, so calls can
    /// route to it immediately. The TCP connect is retried for a few seconds because a freshly-launched
    /// mesh races startup — a dial can beat the target's `listen`.
    public func connect(host: String, port: UInt16) async throws
    {
        let connection = try await dialWithRetry(host: host, port: port)
        try await connection.awaitHandshake(timeout: .seconds(3))
    }

    /// The remote `nodeID`s this node currently has a live connection to (inbound *or* outbound). A
    /// peer polls this to wait until the whole mesh is wired before it starts chatting, so its first
    /// post reaches every peer instead of racing links that are still being dialed in.
    public func connectedNodeIDs() -> Set<String>
    {
        lock.withLock { Set(connections.keys) }
    }

    /// Open one outbound connection to `host:port` (sends our `hello` on start). The returned
    /// ``TCPConnection`` is awaited via `awaitHandshake` to learn when the peer's `hello` came back.
    private func dial(host: String, port: UInt16) throws -> TCPConnection
    {
        let fd = try tcpConnect(host: host, port: port)
        let connection = TCPConnection(fd: fd, system: self)
        connection.start()
        return connection
    }

    /// `dial`, retrying the (blocking) TCP connect while the peer's listener is still coming up.
    private func dialWithRetry(host: String, port: UInt16) async throws -> TCPConnection
    {
        var lastError: Error?
        for attempt in 0 ..< 50 { // ~5s of 100ms retries
            do {
                return try dial(host: host, port: port)
            }
            catch {
                lastError = error
                if attempt < 49 { try await Task.sleep(for: .milliseconds(100)) }
            }
        }
        throw lastError ?? TCPError.notConnected
    }

    // MARK: - DistributedActorSystem

    public func assignID<Act>(_ actorType: Act.Type) -> ActorID
        where Act: DistributedActor, Act.ID == ActorID
    {
        TCPActorID(nodeID: nodeID, name: "actomaton")
    }

    public func actorReady<Act>(_ actor: Act)
        where Act: DistributedActor, Act.ID == ActorID
    {
        lock.withLock {
            localActors[actor.id] = actor
        }
    }

    public func resignID(_ id: ActorID)
    {
        lock.withLock {
            _ = localActors.removeValue(forKey: id)
        }
    }

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID
    {
        if id.nodeID == nodeID {
            guard let actor = lock.withLock({ localActors[id] }) else {
                throw TCPError.actorNotFound(id)
            }
            guard let typed = actor as? Act else {
                throw TCPError.actorNotFound(id)
            }
            return typed
        }
        // Remote: returning nil makes Swift synthesize a proxy.
        return nil
    }

    public func makeInvocationEncoder() -> InvocationEncoder
    {
        TCPInvocationEncoder()
    }

    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
        where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: Codable
    {
        let reply = try await sendInvocation(invocation, to: actor.id, method: target.identifier)
        if let message = reply.errorMessage {
            throw TCPError.remote(message)
        }
        guard let payload = reply.payload else {
            throw TCPError.decoding("missing return payload")
        }
        return try JSONDecoder().decode(Res.self, from: payload)
    }

    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
        where Act: DistributedActor, Act.ID == ActorID, Err: Error
    {
        let reply = try await sendInvocation(invocation, to: actor.id, method: target.identifier)
        if let message = reply.errorMessage {
            throw TCPError.remote(message)
        }
    }

    private func sendInvocation(
        _ encoder: InvocationEncoder,
        to target: TCPActorID,
        method: String
    ) async throws -> TCPReplyEnvelope
    {
        let connection = try await connection(for: target.nodeID)
        let callID = UUID()
        let envelope = TCPInvocationEnvelope(
            callID: callID,
            target: target,
            method: method,
            genericSubs: encoder.genericSubs,
            arguments: encoder.arguments
        )
        let reply: TCPReplyEnvelope = try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                pendingCalls[callID] = continuation
            }
            connection.send(frame: .invocation(envelope)) // enqueued; non-blocking
        }
        return reply
    }

    /// Look up a ready connection to `nodeID`, failing fast. The client's outbound handshake already
    /// completed in `client(...)`, and a server pushing to a subscriber has that subscriber's
    /// connection from when it dialed in — so a missing connection means the peer is gone. Failing
    /// fast keeps a stale subscriber from stalling a broadcast `TaskGroup` (each push is `try?`-ed).
    private func connection(for nodeID: String) async throws -> TCPConnection
    {
        for attempt in 0 ..< 4 { // ~75ms grace, then give up
            if let connection = lock.withLock({ connections[nodeID] }), connection.isReady {
                return connection
            }
            if attempt < 3 { try await Task.sleep(for: .milliseconds(25)) }
        }
        throw TCPError.notConnected
    }

    // MARK: - Listening

    private func startListening(port: UInt16) throws
    {
        let listenFD = try tcpListen(port: port)

        // `accept()` blocks forever, so it gets its own thread — a blocking syscall must stay off
        // Swift's cooperative pool. A `Thread`, not a GCD queue: a long-lived blocking loop parks a
        // GCD worker, and the per-connection `writeQueue`s are GCD too, so keep that pool free.
        Thread.detachNewThread { [weak self] in
            self?.acceptLoop(listenFD)
        }
    }

    private func acceptLoop(_ listenFD: Int32)
    {
        while true {
            guard let clientFD = try? tcpAccept(listenFD) else { continue }
            TCPConnection(fd: clientFD, system: self).start()
        }
    }

    // MARK: - Frame handling (called from a TCPConnection's read loop)

    func handle(_ frame: TCPFrame, on connection: TCPConnection)
    {
        switch frame {
        case let .hello(remoteNodeID):
            lock.withLock {
                connection.remoteNodeID = remoteNodeID
                connection.isReady = true
                connections[remoteNodeID] = connection
            }
            connection.handshakeCompleted()

        case let .invocation(envelope):
            // Execute the call (and write its reply) without blocking the read loop, so this
            // connection can keep reading further frames.
            Task {
                await self.dispatch(envelope, on: connection)
            }

        case let .reply(envelope):
            let continuation = lock.withLock { pendingCalls.removeValue(forKey: envelope.callID) }
            continuation?.resume(returning: envelope)
        }
    }

    func connectionClosed(_ connection: TCPConnection)
    {
        lock.withLock {
            if let id = connection.remoteNodeID, connections[id] === connection {
                connections[id] = nil
            }
        }
    }

    private func dispatch(_ envelope: TCPInvocationEnvelope, on connection: TCPConnection) async
    {
        let reply: TCPReplyEnvelope
        if let actor = lock.withLock({ localActors[envelope.target] }) {
            var decoder = TCPInvocationDecoder(envelope: envelope)
            let handler = TCPResultHandler(callID: envelope.callID)
            do {
                try await executeDistributedTarget(
                    on: actor,
                    target: RemoteCallTarget(envelope.method),
                    invocationDecoder: &decoder,
                    handler: handler
                )
                reply = handler.takeReply()
                    ?? TCPReplyEnvelope(callID: envelope.callID, payload: nil, errorMessage: "no reply recorded")
            }
            catch {
                reply = TCPReplyEnvelope(callID: envelope.callID, payload: nil, errorMessage: "\(error)")
            }
        }
        else {
            reply = TCPReplyEnvelope(callID: envelope.callID, payload: nil, errorMessage: "unknown actor \(envelope.target)")
        }
        connection.send(frame: .reply(reply))
    }
}
