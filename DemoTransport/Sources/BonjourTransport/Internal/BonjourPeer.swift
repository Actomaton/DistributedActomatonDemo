import Foundation
import Network

final class BonjourPeer: @unchecked Sendable
{
    let connection: NWConnection
    weak var system: BonjourActorSystem?
    var remoteNodeID: UUID?
    var remoteNickname: String?
    var isReady: Bool = false
    let expectedRemoteNodeID: UUID?
    private var helloSent = false
    private let stateLock = NSLock()

    init(connection: NWConnection, system: BonjourActorSystem, expectedRemoteNodeID: UUID?)
    {
        self.connection = connection
        self.system = system
        self.expectedRemoteNodeID = expectedRemoteNodeID
    }

    func start(sendHelloImmediately: Bool)
    {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, let system = self.system else { return }
            print("Peer \(self.expectedRemoteNodeID?.uuidString.prefix(8) ?? "inbound") state=\(state)")
            switch state {
            case .ready:
                self.sendHelloIfNeeded(system: system)
                self.receiveFrame()
            case .failed, .cancelled:
                system.peerDidDisconnect(self)
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func sendHelloIfNeeded(system: BonjourActorSystem)
    {
        stateLock.lock()
        if helloSent {
            stateLock.unlock()
            return
        }
        helloSent = true
        stateLock.unlock()
        let hello = BonjourHelloPayload(nodeID: system.localNodeID, nickname: system.nickname)
        do {
            let data = try JSONEncoder().encode(BonjourFrame.hello(hello))
            send(framed: data)
        }
        catch {
            print("[Bonjour error] " + "Failed to encode hello: \(error.localizedDescription)")
        }
    }

    func send(framed data: Data)
    {
        var length = UInt32(data.count).bigEndian
        var out = Data()
        withUnsafeBytes(of: &length) {
            out.append(contentsOf: $0)
        }
        out.append(data)
        connection.send(content: out, completion: .contentProcessed { error in
            if let error = error {
                print("[Bonjour error] " + "send failure: \(error.localizedDescription)")
            }
        })
    }

    private func receiveFrame()
    {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                print("[Bonjour error] " + "recv length err: \(error.localizedDescription)")
                self.connection.cancel()
                return
            }
            guard let header = data, header.count == 4 else {
                if isComplete {
                    self.connection.cancel()
                }
                return
            }
            let length = header.withUnsafeBytes { raw -> UInt32 in
                let v = raw.loadUnaligned(as: UInt32.self)
                return UInt32(bigEndian: v)
            }
            self.receivePayload(length: Int(length))
        }
    }

    private func receivePayload(length: Int)
    {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self = self, let system = self.system else { return }
            if let error = error {
                print("[Bonjour error] " + "recv body err: \(error.localizedDescription)")
                self.connection.cancel()
                return
            }
            guard let data = data, data.count == length else {
                if isComplete {
                    self.connection.cancel()
                }
                return
            }
            do {
                let frame = try JSONDecoder().decode(BonjourFrame.self, from: data)
                system.handleIncomingFrame(frame, from: self)
            }
            catch {
                print("[Bonjour error] " + "frame decode err: \(error.localizedDescription)")
            }
            self.receiveFrame()
        }
    }
}
