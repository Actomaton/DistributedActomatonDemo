import Dispatch
import Foundation

/// One TCP connection. Symmetric: it sends its own `hello` on start, then a read loop dispatches
/// inbound `invocation`s (replying on the same socket) and resumes the continuations of outbound
/// calls on `reply`.
///
/// Writes go on a private serial queue and the read loop on its own thread — both to keep blocking
/// socket I/O off Swift's cooperative pool (see `writeQueue` / `start()`).
final class TCPConnection: @unchecked Sendable
{
    let fd: Int32
    weak var system: TCPActorSystem?
    var remoteNodeID: String?
    var isReady = false

    /// Serializes writes off the caller: `send(frame:)` runs on the cooperative pool but `write()`
    /// blocks, which would park a pool thread (and can deadlock under push fan-out). Serial ⇒ writes
    /// also stay in wire order.
    private let writeQueue = DispatchQueue(label: "TCPActorSystem.write")

    private let stateLock = NSLock()
    private var helloSent = false

    /// Per-connection handshake gate: an outbound dialer (`client` / `connect`) awaits it, and the
    /// peer's `hello` (via `handshakeCompleted`) resumes it — or `awaitHandshake`'s timeout fails it.
    /// Inbound (accepted) connections are never awaited, so their gate simply goes unused.
    private var handshakeWaiter: CheckedContinuation<Void, Error>?
    private var handshakeDone = false

    init(fd: Int32, system: TCPActorSystem)
    {
        self.fd = fd
        self.system = system
    }

    func start()
    {
        sendHelloFrame()

        // `recv()` blocks forever — own thread, off the cooperative pool (a `Thread` not GCD, as with
        // the accept loop). Strong-captures `self`, so the connection lives until the socket closes.
        Thread.detachNewThread {
            self.readLoop()
        }
    }

    /// Signal that this connection's peer `hello` has been processed (called by the system).
    func handshakeCompleted()
    {
        let waiter: CheckedContinuation<Void, Error>? = stateLock.withLock {
            handshakeDone = true
            defer {
                handshakeWaiter = nil
            }
            return handshakeWaiter
        }
        waiter?.resume()
    }

    /// Suspend until this connection's peer `hello` has been processed, or fail after `timeout`.
    func awaitHandshake(timeout: Duration) async throws
    {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.failHandshake()
        }
        defer {
            timeoutTask.cancel()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let alreadyDone = stateLock.withLock { () -> Bool in
                if handshakeDone { return true }
                handshakeWaiter = continuation
                return false
            }
            if alreadyDone {
                continuation.resume()
            }
        }
    }

    /// Resume a pending `awaitHandshake` with failure (timeout). A later `hello` finds `nil` ⇒ no-op.
    private func failHandshake()
    {
        let waiter: CheckedContinuation<Void, Error>? = stateLock.withLock {
            guard !handshakeDone else { return nil }
            defer {
                handshakeWaiter = nil
            }
            return handshakeWaiter
        }
        waiter?.resume(throwing: TCPError.notConnected)
    }

    /// Enqueue a frame; the actual (blocking) socket write happens on `writeQueue`, off the caller.
    func send(frame: TCPFrame)
    {
        writeQueue.async { [fd] in
            guard let data = try? JSONEncoder().encode(frame) else { return }
            try? writeFrame(fd, data)
        }
    }

    private func sendHelloFrame()
    {
        guard let system else { return }
        stateLock.lock()
        let already = helloSent
        helloSent = true
        stateLock.unlock()
        guard !already else { return }
        send(frame: .hello(nodeID: system.nodeID))
    }

    private func readLoop()
    {
        defer {
            closeFD(fd)
            system?.connectionClosed(self)
        }
        while true {
            guard let data = try? readFrame(fd),
                  let frame = try? JSONDecoder().decode(TCPFrame.self, from: data),
                  let system
            else { return }
            system.handle(frame, on: self)
        }
    }
}
