import Distributed
import Foundation
import Network

/// Minimal `DistributedActorSystem` that discovers peers over Bonjour and carries Codable-encoded
/// distributed-call envelopes over length-prefixed TCP frames.
///
/// ## One actor per node
///
/// `assignID` hands out a single well-known ID per node (node UUID + ``actorName``), and peer
/// discovery reconstructs a remote ID from just the discovered node UUID + the same well-known name.
/// So each node hosts exactly one `DistributedActomaton` — which is precisely the demos' topology
/// (one actomaton per peer / per client / per server).
public final class BonjourActorSystem: DistributedActorSystem, @unchecked Sendable
{
    public typealias ActorID = BonjourActorID
    public typealias InvocationEncoder = BonjourInvocationEncoder
    public typealias InvocationDecoder = BonjourInvocationDecoder
    public typealias SerializationRequirement = any Codable
    public typealias ResultHandler = BonjourResultHandler

    public let localNodeID: UUID
    public let nickname: String

    /// The well-known name every node assigns to its single hosted actor.
    public let actorName: String

    private let serviceType: String
    private let queue = DispatchQueue(label: "BonjourActorSystem")

    private let lock = NSLock()
    private var localActors: [BonjourActorID: any DistributedActor] = [:]
    private var pendingCalls: [UUID: CheckedContinuation<BonjourReplyEnvelope, Error>] = [:]
    private var peers: [UUID: BonjourPeer] = [:]
    private var pendingInboundPeers: [ObjectIdentifier: BonjourPeer] = [:]
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var lastBrowseResults: Set<NWBrowser.Result> = []

    // Observers of peer set changes. Closure payload: (nodeID, nickname).
    private var peerObservers: [UUID: @Sendable ([(UUID, String)]) -> Void] = [:]

    public init(
        nickname: String,
        actorName: String = "actomaton",
        serviceType: String = "_actomaton._tcp"
    )
    {
        self.localNodeID = UUID()
        self.nickname = nickname
        self.actorName = actorName
        self.serviceType = serviceType
    }

    // MARK: Lifecycle

    public func start() throws
    {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let listener = try NWListener(using: params)
        listener.service = NWListener.Service(
            name: localNodeID.uuidString,
            type: serviceType
        )
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleInbound(conn)
        }
        listener.stateUpdateHandler = { state in
            print("listener state: \(state)")
        }
        listener.serviceRegistrationUpdateHandler = { update in
            print("service registration: \(update)")
        }
        listener.start(queue: queue)
        self.listener = listener

        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleBrowseResults(results)
        }
        browser.stateUpdateHandler = { state in
            print("browser state: \(state)")
        }
        browser.start(queue: queue)
        self.browser = browser

        print("Started node \(self.localNodeID.uuidString) nickname=\(self.nickname)")
    }

    public func stop()
    {
        listener?.cancel()
        browser?.cancel()
        lock.lock()
        let peerConns = peers.values.map(\.connection)
        peers.removeAll()
        lock.unlock()
        peerConns.forEach {
            $0.cancel()
        }
    }

    // MARK: Peer observation (used by UI)

    public func observePeers(_ handler: @escaping @Sendable ([PeerInfo]) -> Void) -> UUID
    {
        let token = UUID()
        let shim: @Sendable ([(UUID, String)]) -> Void = { entries in
            handler(entries.map {
                PeerInfo(nodeID: $0.0, nickname: $0.1)
            })
        }
        lock.lock()
        peerObservers[token] = shim
        let snapshot = peers.values
            .filter {
                $0.remoteNodeID != nil
            }
            .map {
                ($0.remoteNodeID!, $0.remoteNickname ?? "?")
            }
        lock.unlock()
        shim(snapshot)
        return token
    }

    public func removePeerObserver(_ token: UUID)
    {
        lock.lock()
        defer {
            lock.unlock()
        }
        peerObservers.removeValue(forKey: token)
    }

    private func notifyPeersChanged()
    {
        lock.lock()
        let snapshot = peers.values
            .filter {
                $0.remoteNodeID != nil
            }
            .map {
                ($0.remoteNodeID!, $0.remoteNickname ?? "?")
            }
        let observers = Array(peerObservers.values)
        lock.unlock()
        for obs in observers {
            obs(snapshot)
        }
    }

    // MARK: DistributedActorSystem

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID
    {
        lock.lock()
        defer {
            lock.unlock()
        }
        if id.nodeID == localNodeID {
            guard let actor = localActors[id] else {
                throw BonjourActorSystemError.actorNotFound(id)
            }
            guard let typed = actor as? Act else {
                throw BonjourActorSystemError.actorNotFound(id)
            }
            return typed
        }
        // Remote: returning nil makes Swift synthesize a proxy.
        return nil
    }

    public func assignID<Act>(_ actorType: Act.Type) -> ActorID
        where Act: DistributedActor, Act.ID == ActorID
    {
        // One singleton actor per node (see the type doc). The well-known name lets peers address
        // this actor from just the discovered node UUID.
        return BonjourActorID(nodeID: localNodeID, name: actorName)
    }

    public func actorReady<Act>(_ actor: Act)
        where Act: DistributedActor, Act.ID == ActorID
    {
        lock.lock()
        defer {
            lock.unlock()
        }
        localActors[actor.id] = actor
    }

    public func resignID(_ id: ActorID)
    {
        lock.lock()
        defer {
            lock.unlock()
        }
        localActors.removeValue(forKey: id)
    }

    public func makeInvocationEncoder() -> InvocationEncoder
    {
        BonjourInvocationEncoder()
    }

    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
        where Act: DistributedActor, Act.ID == ActorID,
              Err: Error, Res: Codable
    {
        let reply = try await sendInvocation(
            to: actor.id,
            target: target,
            invocation: invocation
        )
        if let msg = reply.errorMessage {
            throw BonjourActorSystemError.remote(msg)
        }
        guard let data = reply.payload else {
            throw BonjourActorSystemError.decodingFailure("missing payload for non-void return")
        }
        return try JSONDecoder().decode(Res.self, from: data)
    }

    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
        where Act: DistributedActor, Act.ID == ActorID, Err: Error
    {
        let reply = try await sendInvocation(
            to: actor.id,
            target: target,
            invocation: invocation
        )
        if let msg = reply.errorMessage {
            throw BonjourActorSystemError.remote(msg)
        }
    }

    private func sendInvocation(
        to actorID: BonjourActorID,
        target: RemoteCallTarget,
        invocation: InvocationEncoder
    ) async throws -> BonjourReplyEnvelope
    {
        let callID = UUID()
        let env = BonjourInvocationEnvelope(
            callID: callID,
            target: actorID,
            method: target.identifier,
            genericSubs: invocation.genericSubs,
            arguments: invocation.arguments
        )
        let peerID = actorID.nodeID
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            pendingCalls[callID] = cont
            let peer = peers[peerID]
            lock.unlock()
            guard let peer = peer, peer.isReady else {
                lock.lock()
                pendingCalls.removeValue(forKey: callID)
                lock.unlock()
                cont.resume(throwing: BonjourActorSystemError.peerNotConnected(peerID))
                return
            }
            do {
                let data = try JSONEncoder().encode(BonjourFrame.invocation(env))
                peer.send(framed: data)
            } catch {
                lock.lock()
                pendingCalls.removeValue(forKey: callID)
                lock.unlock()
                cont.resume(throwing: error)
            }
        }
    }

    func sendReply(_ reply: BonjourReplyEnvelope, toNode nodeID: UUID)
    {
        lock.lock()
        let peer = peers[nodeID]
        lock.unlock()
        guard let peer = peer else {
            print("[Bonjour error] " + "Cannot send reply: peer \(nodeID) not connected")
            return
        }
        do {
            let data = try JSONEncoder().encode(BonjourFrame.reply(reply))
            peer.send(framed: data)
        } catch {
            print("[Bonjour error] " + "Failed to encode reply: \(error.localizedDescription)")
        }
    }

    // MARK: Connection handling

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>)
    {
        print("browse results: \(results.count)")
        lock.lock()
        lastBrowseResults = results
        lock.unlock()
        dialMissingPeers(from: results)
    }

    private func dialMissingPeers(from results: Set<NWBrowser.Result>)
    {
        for r in results {
            print("  - \(r.endpoint)")
            guard case .service(let name, _, _, _) = r.endpoint else { continue }
            guard let peerID = UUID(uuidString: name) else { continue }
            if peerID == localNodeID { continue }
            // Tie-break: only the numerically lower UUID initiates, to avoid duplicates.
            if localNodeID.uuidString < peerID.uuidString {
                lock.lock()
                let already = peers[peerID] != nil
                lock.unlock()
                if already { continue }
                connectOutbound(to: r.endpoint, expectedPeer: peerID)
            }
        }
    }

    private func connectOutbound(to endpoint: NWEndpoint, expectedPeer: UUID)
    {
        print("connecting outbound to \(endpoint)")
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let conn = NWConnection(to: endpoint, using: params)
        let peer = BonjourPeer(connection: conn, system: self, expectedRemoteNodeID: expectedPeer)
        lock.lock()
        peers[expectedPeer] = peer
        lock.unlock()
        peer.start(sendHelloImmediately: true)
    }

    private func handleInbound(_ conn: NWConnection)
    {
        print("accepted inbound from \(conn.endpoint)")
        let peer = BonjourPeer(connection: conn, system: self, expectedRemoteNodeID: nil)
        lock.lock()
        pendingInboundPeers[ObjectIdentifier(peer)] = peer
        lock.unlock()
        peer.start(sendHelloImmediately: true)
    }

    func peerDidReceiveHello(_ peer: BonjourPeer, hello: BonjourHelloPayload)
    {
        lock.lock()
        pendingInboundPeers.removeValue(forKey: ObjectIdentifier(peer))
        if let existing = peers[hello.nodeID], existing !== peer {
            // Duplicate connection — drop the newer one.
            lock.unlock()
            peer.connection.cancel()
            return
        }
        peer.remoteNodeID = hello.nodeID
        peer.remoteNickname = hello.nickname
        peer.isReady = true
        peers[hello.nodeID] = peer
        lock.unlock()
        print("peer ready: \(hello.nodeID.uuidString.prefix(8)) \(hello.nickname)")
        notifyPeersChanged()
    }

    func peerDidDisconnect(_ peer: BonjourPeer)
    {
        lock.lock()
        pendingInboundPeers.removeValue(forKey: ObjectIdentifier(peer))
        if let id = peer.remoteNodeID, peers[id] === peer {
            peers.removeValue(forKey: id)
        }
        // Also clear any slot reserved before the hello arrived for outbound peers,
        // otherwise a connection that fails before handshake leaks the slot and
        // blocks future re-dials in `dialMissingPeers`.
        if let id = peer.expectedRemoteNodeID, peers[id] === peer {
            peers.removeValue(forKey: id)
        }
        let snapshot = lastBrowseResults
        lock.unlock()
        notifyPeersChanged()
        // Re-evaluate the most recent browse snapshot so a transient TCP loss
        // doesn't permanently strand a peer until the browse set changes again.
        dialMissingPeers(from: snapshot)
    }

    func handleIncomingFrame(_ frame: BonjourFrame, from peer: BonjourPeer)
    {
        switch frame {
        case .hello(let payload):
            peerDidReceiveHello(peer, hello: payload)
            // Respond with our hello if we haven't sent yet — BonjourPeer.start handles the initial send.
        case .invocation(let env):
            Task {
                await dispatchIncomingInvocation(env, from: peer)
            }
        case .reply(let env):
            lock.lock()
            let cont = pendingCalls.removeValue(forKey: env.callID)
            lock.unlock()
            cont?.resume(returning: env)
        }
    }

    private func dispatchIncomingInvocation(_ env: BonjourInvocationEnvelope, from peer: BonjourPeer) async
    {
        guard let remoteNodeID = peer.remoteNodeID else { return }
        let actor = lock.withLock {
            localActors[env.target]
        }
        guard let actor = actor else {
            sendReply(
                BonjourReplyEnvelope(callID: env.callID, payload: nil,
                                     errorMessage: "unknown actor \(env.target)"),
                toNode: remoteNodeID
            )
            return
        }
        var decoder = BonjourInvocationDecoder(envelope: env)
        let handler = BonjourResultHandler(
            callID: env.callID,
            peerNodeID: remoteNodeID,
            system: self
        )
        do {
            try await executeDistributedTarget(
                on: actor,
                target: RemoteCallTarget(env.method),
                invocationDecoder: &decoder,
                handler: handler
            )
        } catch {
            sendReply(
                BonjourReplyEnvelope(callID: env.callID, payload: nil,
                                     errorMessage: "\(error)"),
                toNode: remoteNodeID
            )
        }
    }

    // MARK: Snapshot helpers (for discovery-based wiring)

    /// The IDs of every currently-connected peer's singleton actor (node UUID + ``actorName``).
    public func currentPeerIDs() -> [BonjourActorID]
    {
        lock.lock()
        defer {
            lock.unlock()
        }
        return peers.values.compactMap { peer in
            guard let id = peer.remoteNodeID, peer.isReady else { return nil }
            return BonjourActorID(nodeID: id, name: actorName)
        }
    }
}
