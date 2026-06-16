import Distributed
import DistributedActomaton
import Foundation
import PeerToPeerCore
import TCPTransport

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// Headless, cross-OS peer-to-peer chat demo over a real TCP transport. It reuses the SAME
// `ChatPeerActomaton` reducer as the InMemory / Bonjour apps (from `PeerToPeerCore`): every peer owns
// its own chat log, and a posted message is fanned out to every other peer as a `.deliver` reverse
// letter.
//
//   PeerToPeerTCPDemo peer      <nodeID> <port> [peerSpec ...]   # interactive: type to post
//   PeerToPeerTCPDemo peer-auto <nodeID> <port> [peerSpec ...]   # scripted: post + assert receipt
//
// where peerSpec = nodeID@host:port  (the address of ANOTHER peer in the mesh)
//
// Unlike client-server (where only the server owns state), this is a real **mesh**: each node both
// listens (so peers can dial it) and dials the peers ordered *after* it (so each pair gets exactly one
// bidirectional connection — no duplicate links, no simultaneous-connect tie-break). Every `.deliver`
// round-trips `ChatAction<TCPActorID>` / `ChatState<TCPActorID>` as bound generic substitutions across
// the OS boundary — the interesting thing this verifies, in both directions at once.

/// Writes whole lines straight to stdout's file descriptor (fd 1), bypassing C stdio.
///
/// We deliberately avoid `print` + `fflush`: `fflush(nil)` flushes *every* stream, walking `stdin` too,
/// and a blocking `readLine()` holds `stdin`'s `flockfile` lock while parked in `read()` — so a
/// concurrent `fflush(nil)` from a `publish` effect would deadlock on that lock and wedge the serial
/// effect queue. A raw `write(2)` needs no flush, never touches `stdin`, and (under the lock, for one
/// short line) is atomic, so concurrent effect tasks don't interleave their output.
enum Out
{
    private static let lock = NSLock()

    static func line(_ string: String)
    {
        let bytes = Array((string + "\n").utf8)
        lock.withLock {
            var offset = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBytes { write(1, $0.baseAddress, $0.count) }
                if n <= 0 { break }
                offset += n
            }
        }
    }
}

/// One peer's address on the command line: `nodeID@host:port`.
struct PeerSpec
{
    let nodeID: String
    let host: String
    let port: UInt16

    /// The well-known actor ID of that peer's `ChatPeerActomaton` (`assignID` names it `"actomaton"`).
    var actorID: TCPActorID { TCPActorID(nodeID: nodeID, name: "actomaton") }

    init?(_ raw: String)
    {
        guard let at = raw.firstIndex(of: "@") else { return nil }
        let nodeID = String(raw[..<at])
        let hostPort = raw[raw.index(after: at)...]
        guard let colon = hostPort.lastIndex(of: ":") else { return nil }
        let host = String(hostPort[..<colon])
        guard let port = UInt16(hostPort[hostPort.index(after: colon)...]),
              !nodeID.isEmpty, !host.isEmpty
        else { return nil }
        self.nodeID = nodeID
        self.host = host
        self.port = port
    }
}

/// Prints each newly-committed chat-log line exactly once (the reducer's `publish` fires on every
/// commit — `.connect`, the local `.post` echo, and each remote `.deliver`). Locking + a high-water
/// mark keep it correct under the concurrent effect tasks that drive `publish`.
final class ChatPrinter: @unchecked Sendable
{
    private let lock = NSLock()
    private var printed = 0
    private let me: String

    init(me: String) { self.me = me }

    func render(_ state: ChatState<TCPActorID>)
    {
        let lines = lock.withLock { () -> [String] in
            var out: [String] = []
            while printed < state.log.count {
                let msg = state.log[printed]
                printed += 1
                out.append("  [\(msg.sender == me ? "you" : msg.sender)] \(msg.text)")
            }
            return out
        }
        guard !lines.isEmpty else { return }
        lines.forEach { Out.line($0) }
    }
}

actor ChatStateMirror
{
    private var state: ChatState<TCPActorID>

    init(nodeID: String)
    {
        self.state = ChatState(name: nodeID)
    }

    func publish(_ state: ChatState<TCPActorID>)
    {
        self.state = state
    }

    func current() -> ChatState<TCPActorID>
    {
        state
    }
}

func waitForChatState(
    mirror: ChatStateMirror,
    timeout: Duration = .seconds(10),
    matching predicate: @Sendable (ChatState<TCPActorID>) -> Bool
) async -> ChatState<TCPActorID>?
{
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        let state = await mirror.current()

        if predicate(state) {
            return state
        }

        try? await Task.sleep(for: .milliseconds(50))
    }

    let state = await mirror.current()
    return predicate(state) ? state : nil
}

/// Builds this node's `ChatPeerActomaton`, mirroring every committed state into `printer`.
func makePeer(
    system: TCPActorSystem,
    nodeID: String,
    printer: ChatPrinter,
    mirror: ChatStateMirror
) -> ChatPeerActomaton<TCPActorSystem>
{
    let env = ChatEnv(system: system, publish: { state in
        printer.render(state)

        Task {
            await mirror.publish(state)
        }
    })
    return ChatPeerActomaton<TCPActorSystem>(
        state: ChatState(name: nodeID),
        reducer: makeChatReducer(),
        environment: env,
        actorSystem: system
    )
}

/// Wires this node into the mesh: dials every peer ordered *after* this node's id (so each pair is
/// dialed by exactly one side), then waits until the inbound links from the peers ordered *before* it
/// are up too — so the first post reaches every peer rather than racing connections still being dialed.
func formMesh(_ system: TCPActorSystem, nodeID: String, peers: [PeerSpec]) async
{
    for peer in peers where peer.nodeID > nodeID {
        do {
            try await system.connect(host: peer.host, port: peer.port)
            Out.line("[\(nodeID)] dialed \(peer.nodeID)@\(peer.host):\(peer.port)")
        }
        catch {
            Out.line("[\(nodeID)] failed to dial \(peer.nodeID): \(error)")
        }
    }

    let wanted = Set(peers.map(\.nodeID))
    for _ in 0 ..< 100 where !system.connectedNodeIDs().isSuperset(of: wanted) { // ~10s
        try? await Task.sleep(for: .milliseconds(100))
    }

    let connected = system.connectedNodeIDs()
    if connected.isSuperset(of: wanted) {
        Out.line("[\(nodeID)] mesh ready — connected to [\(connected.sorted().joined(separator: ", "))]")
    }
    else {
        Out.line("[\(nodeID)] mesh incomplete — connected to \(connected.sorted()), wanted \(wanted.sorted())")
    }
}

/// Interactive chat: each typed line is posted to the mesh; incoming `.deliver`s print as they arrive.
///
/// `readLine()` blocks, so it reads on its own thread and bridges lines in via `AsyncStream` — keeping
/// the blocking call off a Swift-concurrency cooperative-pool worker (which the effect tasks need free).
func runInteractive(peer: ChatPeerActomaton<TCPActorSystem>) async throws
{
    Out.line("Type a message and press Return to post it to the mesh · 'quit' to exit")

    let (lines, continuation) = AsyncStream.makeStream(of: String.self)
    Thread.detachNewThread {
        while let line = readLine() {
            continuation.yield(line)
        }
        continuation.finish() // stdin closed (EOF)
    }

    for await line in lines {
        switch line.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "":
            continue
        case "quit", "q", "exit":
            exit(0)
        case let text:
            try await peer.send(.post(text))
        }
    }
}

/// Scripted self-check: post our own greeting, then converge once we have *received* every other
/// peer's greeting (their `.deliver` reverse letters landed in our local log). Each peer running this
/// verifies inbound delivery from every other peer — together the whole mesh is exercised both ways.
func runAuto(
    peer: ChatPeerActomaton<TCPActorSystem>,
    nodeID: String,
    peers: [PeerSpec],
    mirror: ChatStateMirror
) async throws
{
    let greeting = "ping from \(nodeID)"
    try await peer.send(.post(greeting))
    Out.line("[\(nodeID)] posted: \(greeting)")

    let expected = peers.map { "ping from \($0.nodeID)" }
    if let state = await waitForChatState(
        mirror: mirror,
        matching: { state in
            let texts = state.log.map(\.text)
            return expected.allSatisfy(texts.contains)
        }
    ) {
        let texts = state.log.map(\.text)
        let received = expected.filter(texts.contains)
        Out.line("✅ peer-to-peer mesh OK — \(nodeID) received: [\(received.sorted().joined(separator: ", "))]")
        // Let peers finish reading our greeting before we tear the socket down.
        try? await Task.sleep(for: .milliseconds(300))
        exit(0)
    }

    let texts = await mirror.current().log.map(\.text)
    let missing = expected.filter { !texts.contains($0) }
    Out.line("❌ \(nodeID) did not receive: [\(missing.sorted().joined(separator: ", "))]")
    exit(1)
}

// MARK: - Entry point

let arguments = CommandLine.arguments
let role = arguments.count > 1 ? arguments[1] : "help"

switch role {
case "peer", "peer-auto":
    guard arguments.count > 3, let port = UInt16(arguments[3]) else {
        Out.line("usage: PeerToPeerTCPDemo \(role) <nodeID> <port> [nodeID@host:port ...]")
        exit(1)
    }
    let nodeID = arguments[2]
    let peers = arguments.dropFirst(4).compactMap(PeerSpec.init)

    let system = try TCPActorSystem.peer(nodeID: nodeID, port: port)
    let printer = ChatPrinter(me: nodeID)
    let mirror = ChatStateMirror(nodeID: nodeID)
    let peer = makePeer(system: system, nodeID: nodeID, printer: printer, mirror: mirror)
    Out.line("[\(nodeID)] listening on \(port); actorID=\(peer.id)")

    await formMesh(system, nodeID: nodeID, peers: peers)

    // Register the full peer set so a post fans out to every other peer.
    try await peer.send(.connect(peers: peers.map(\.actorID)))

    if role == "peer-auto" {
        try await runAuto(peer: peer, nodeID: nodeID, peers: peers, mirror: mirror)
    }
    else {
        try await runInteractive(peer: peer)
    }

default:
    Out.line("""
    usage:
      PeerToPeerTCPDemo peer      <nodeID> <port> [nodeID@host:port ...]   # interactive chat
      PeerToPeerTCPDemo peer-auto <nodeID> <port> [nodeID@host:port ...]   # scripted self-check
    """)
}
