import ClientServerCore
import Distributed
import DistributedActomaton
import Foundation
import TCPTransport

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// Headless, cross-OS client-server demo over a real TCP transport. It reuses the SAME `ServerActomaton`
// reducer as the InMemory / Bonjour apps (from `ClientServerCore`): the server owns the counter, and
// clients send `.increment` / `.reset` commands.
//
//   ClientServerTCPDemo server      [port]
//   ClientServerTCPDemo client      <host> [port] [name]   # interactive: type commands
//   ClientServerTCPDemo client-auto <host> [port]          # scripted: +5, +37, then assert count == 42
//
// Interaction uses the same push-based client-server path as the SwiftUI demos: the CLI client hosts
// a local `ClientActomaton`, subscribes that receiver with the server, then observes snapshots pushed
// back over TCP. This still round-trips `ServerAction<TCPActorID>` and `ServerSnapshot` across the OS
// boundary, while keeping the verification on the supported action-broadcast path.

actor SnapshotMirror
{
    private var version = 0
    private var snapshot = ServerSnapshot()

    func publish(_ snapshot: ServerSnapshot)
    {
        version += 1
        self.snapshot = snapshot
    }

    func current() -> (version: Int, snapshot: ServerSnapshot)
    {
        (version, snapshot)
    }
}

func makeReceiver(system: TCPActorSystem) -> (ClientActomaton<TCPActorSystem>, SnapshotMirror)
{
    let mirror = SnapshotMirror()
    let receiver = ClientActomaton<TCPActorSystem>(
        state: ClientState(),
        reducer: clientReducer,
        environment: ClientEnv(publish: { snapshot in
            Task {
                await mirror.publish(snapshot)
            }
        }),
        actorSystem: system
    )
    return (receiver, mirror)
}

func waitForSnapshot(
    mirror: SnapshotMirror,
    after minVersion: Int? = nil,
    timeout: Duration = .seconds(5),
    matching predicate: @Sendable (ServerSnapshot) -> Bool
) async -> (version: Int, snapshot: ServerSnapshot)?
{
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        let current = await mirror.current()
        let isNewEnough = minVersion.map { current.version > $0 } ?? true

        if isNewEnough && predicate(current.snapshot) {
            return current
        }

        try? await Task.sleep(for: .milliseconds(50))
    }

    let current = await mirror.current()
    let isNewEnough = minVersion.map { current.version > $0 } ?? true
    return isNewEnough && predicate(current.snapshot) ? current : nil
}

/// Prints the latest server snapshot the client received.
func printSnapshot(_ snapshot: ServerSnapshot)
{
    let last = snapshot.events.last.map { " (\($0.text))" } ?? ""
    print("→ count = \(snapshot.count)\(last)")
    fflush(nil)
}

let serverID = TCPActorID(nodeID: "server", name: "actomaton")

let arguments = CommandLine.arguments
let role = arguments.count > 1 ? arguments[1] : "help"

switch role {
case "server":
    let port = UInt16(arguments.count > 2 ? arguments[2] : "9099") ?? 9099
    let system = try TCPActorSystem.server(nodeID: "server", port: port)
    let server = ServerActomaton<TCPActorSystem>(
        state: ServerState(),
        reducer: makeServerReducer(),
        environment: ServerEnv(system: system, publish: { state in
            print("[server] count=\(state.count)")
            fflush(nil)
        }),
        actorSystem: system
    )
    print("[server] ready on port \(port); actorID=\(server.id)")
    fflush(nil) // flush all streams (don't reference the `stdout` global; not Sendable on Glibc)

    // Serve forever: the accept loop runs on its own thread; keep the main task alive (suspended).
    while true {
        try await Task.sleep(for: .seconds(3600))
    }

case "client":
    // Interactive: type commands; the resulting count is polled and printed after each.
    let host = arguments.count > 2 ? arguments[2] : "127.0.0.1"
    let port = UInt16(arguments.count > 3 ? arguments[3] : "9099") ?? 9099
    let name = arguments.count > 4 ? arguments[4] : "tcp-client"

    let system = try await TCPActorSystem.client(nodeID: "client", serverHost: host, serverPort: port)
    let server = try ServerActomaton<TCPActorSystem>.resolve(id: serverID, using: system)
    let (receiver, snapshots) = makeReceiver(system: system)
    print("[client:\(name)] connected to \(host):\(port)")
    print("Commands: a number to add (e.g. 5, -1, +37) · 'reset' · 'quit'  (snapshot prints after each)")
    try await server.send(.subscribe(clientID: receiver.id))

    if let current = await waitForSnapshot(mirror: snapshots, after: 0, matching: { _ in true }) {
        printSnapshot(current.snapshot)
    }
    else {
        print("→ failed to receive initial server snapshot")
        fflush(nil)
    }

    while let line = readLine() {
        switch line.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "":
            continue
        case "quit", "q", "exit":
            exit(0)
        case "reset":
            let before = await snapshots.current().version
            try await server.send(.reset(who: name))
            if let current = await waitForSnapshot(mirror: snapshots, after: before, matching: { _ in true }) {
                printSnapshot(current.snapshot)
            }
        case let command:
            guard let delta = Int(command) else {
                print("?? '\(command)' — type a number, 'reset', or 'quit'")
                fflush(nil)
                continue
            }
            let before = await snapshots.current().version
            try await server.send(.increment(by: delta, who: name))
            if let current = await waitForSnapshot(mirror: snapshots, after: before, matching: { _ in true }) {
                printSnapshot(current.snapshot)
            }
        }
    }

case "client-auto":
    // Scripted self-check (used for automated cross-OS verification).
    let host = arguments.count > 2 ? arguments[2] : "127.0.0.1"
    let port = UInt16(arguments.count > 3 ? arguments[3] : "9099") ?? 9099

    let system = try await TCPActorSystem.client(nodeID: "client", serverHost: host, serverPort: port)
    let server = try ServerActomaton<TCPActorSystem>.resolve(id: serverID, using: system)
    let (receiver, snapshots) = makeReceiver(system: system)
    print("[client-auto] connected to \(host):\(port); sending commands…")

    try await server.send(.subscribe(clientID: receiver.id))
    try await server.send(.reset(who: "tcp-auto"))
    try await server.send(.increment(by: 5, who: "tcp-auto"))
    try await server.send(.increment(by: 37, who: "tcp-auto"))

    guard let current = await waitForSnapshot(mirror: snapshots, matching: { $0.count == 42 }) else {
        let latest = await snapshots.current().snapshot
        print("❌ did not receive expected server count 42; latest=\(latest.count)")
        exit(1)
    }

    let snapshot = current.snapshot
    print("[client-auto] server count=\(snapshot.count)")
    for event in snapshot.events {
        print("  • \(event.text)")
    }

    if snapshot.count == 42 {
        print("✅ cross-node client-server OK — count=42 via the shared ServerActomaton over TCP")
    }
    else {
        print("❌ unexpected server count \(snapshot.count)")
        exit(1)
    }

default:
    print("usage: ClientServerTCPDemo server [port] | client <host> [port] [name] | client-auto <host> [port]")
}
