import Foundation

#if canImport(Glibc)
import Glibc
private let sockStreamType = Int32(SOCK_STREAM.rawValue)
#elseif canImport(Darwin)
import Darwin
private let sockStreamType = SOCK_STREAM
#endif

// A tiny cross-platform POSIX socket layer (blocking, length-prefixed framing). No third-party deps,
// no Bonjour — just enough to carry Codable distributed-call envelopes between a macOS and a Linux
// process. Frame = 4-byte big-endian length + JSON payload.

/// Ignore `SIGPIPE` so a write to a closed peer returns `EPIPE` instead of killing the process.
func ignoreSIGPIPE()
{
    signal(SIGPIPE, SIG_IGN)
}

func closeFD(_ fd: Int32)
{
    close(fd)
}

/// Open a listening TCP socket bound to `0.0.0.0:port` (so a container's published port is reachable).
func tcpListen(port: UInt16) throws -> Int32
{
    let fd = socket(AF_INET, sockStreamType, 0)
    guard fd >= 0 else {
        throw TCPError.io("socket: \(errnoString())")
    }

    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = 0 // INADDR_ANY

    let bound = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0 else {
        closeFD(fd)
        throw TCPError.io("bind(:\(port)): \(errnoString())")
    }
    guard listen(fd, 16) == 0 else {
        closeFD(fd)
        throw TCPError.io("listen: \(errnoString())")
    }
    return fd
}

func tcpAccept(_ listenFD: Int32) throws -> Int32
{
    let fd = accept(listenFD, nil, nil)
    guard fd >= 0 else {
        throw TCPError.io("accept: \(errnoString())")
    }
    return fd
}

/// Resolve `host` (name or IP) via `getaddrinfo` and connect. Works for `localhost`,
/// `host.docker.internal`, or raw IPs.
func tcpConnect(host: String, port: UInt16) throws -> Int32
{
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = sockStreamType

    var result: UnsafeMutablePointer<addrinfo>?
    let status = getaddrinfo(host, String(port), &hints, &result)
    guard status == 0, let info = result else {
        throw TCPError.io("getaddrinfo(\(host)): \(String(cString: gai_strerror(status)))")
    }
    defer {
        freeaddrinfo(result)
    }

    let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
    guard fd >= 0 else {
        throw TCPError.io("socket: \(errnoString())")
    }
    guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
        closeFD(fd)
        throw TCPError.io("connect(\(host):\(port)): \(errnoString())")
    }
    return fd
}

// MARK: - Framing

func writeFrame(_ fd: Int32, _ payload: Data) throws
{
    var header = UInt32(payload.count).bigEndian
    var out = [UInt8]()
    withUnsafeBytes(of: &header) {
        out.append(contentsOf: $0)
    }
    out.append(contentsOf: payload)
    try writeAll(fd, out)
}

func readFrame(_ fd: Int32) throws -> Data
{
    let header = try readFull(fd, 4)
    let length = header.withUnsafeBytes {
        $0.loadUnaligned(as: UInt32.self)
    }
    let count = Int(UInt32(bigEndian: length))
    return Data(try readFull(fd, count))
}

// MARK: - Low-level read/write (handle partial I/O + EINTR)

private func readFull(_ fd: Int32, _ count: Int) throws -> [UInt8]
{
    guard count > 0 else { return [] }
    var buffer = [UInt8](repeating: 0, count: count)
    var total = 0
    try buffer.withUnsafeMutableBytes { raw in
        while total < count {
            let n = recv(fd, raw.baseAddress!.advanced(by: total), count - total, 0)
            if n == 0 {
                throw TCPError.connectionClosed
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw TCPError.io("recv: \(errnoString())")
            }
            total += n
        }
    }
    return buffer
}

private func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws
{
    let count = bytes.count
    var total = 0
    try bytes.withUnsafeBytes { raw in
        while total < count {
            let n = send(fd, raw.baseAddress!.advanced(by: total), count - total, 0)
            if n < 0 {
                if errno == EINTR { continue }
                throw TCPError.io("send: \(errnoString())")
            }
            total += n
        }
    }
}

private func errnoString() -> String
{
    String(cString: strerror(errno))
}
