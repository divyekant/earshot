import Darwin
import EarshotCore
import Foundation
import Security

// The control socket of the command line (R-CT-2, R-CT-3, docs/CONTROL.md). A Unix socket file in the store folder,
// not a network port. Only the same user can open it: the file mode is 0600, and earshot checks the user id of
// each peer. "run --actions" also needs a peer that is this program (the same code signature), so that another
// program cannot use the Accessibility permission of earshot through the socket.

/// The server in the app. Each connection is one request line and one reply line.
final class ControlServer: @unchecked Sendable {
    typealias Handler = (ControlRequest, _ peerIsEarshot: Bool) async -> ControlReply

    /// The longest request line.
    static let maxLine = 64 * 1024
    /// The longest wait for a request line after a connection.
    static let readSeconds = 5

    static func path(_ store: Store) -> String { store.folder.appendingPathComponent("control.sock").path }

    let path: String
    private let handler: Handler
    private var fd: Int32 = -1
    private let lock = NSLock()
    private var collected: [String]?

    init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    struct SocketError: Error, CustomStringConvertible {
        let description: String
    }

    func start() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { throw SocketError(description: "socket: \(errno)") }
        unlink(path)  // A file from an earlier run. Only one earshot runs at a time.
        guard var addr = Self.address(path) else { close(s); throw SocketError(description: "the path is too long: \(path)") }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(s); throw SocketError(description: "bind: \(errno)") }
        chmod(path, 0o600)
        guard listen(s, 4) == 0 else { close(s); throw SocketError(description: "listen: \(errno)") }
        fd = s
        let thread = Thread { [weak self] in self?.acceptLoop(s) }
        thread.name = "earshot.control"
        thread.start()
    }

    func stop() {
        if fd >= 0 { close(fd); fd = -1 }
        unlink(path)
    }

    /// Plugin answers that arrive while a "run" waits (R-CT-4).
    func startCollecting() { lock.lock(); collected = []; lock.unlock() }
    func collect(_ line: String) { lock.lock(); collected?.append(line); lock.unlock() }
    var collectedCount: Int { lock.lock(); defer { lock.unlock() }; return collected?.count ?? 0 }
    func stopCollecting() -> [String] { lock.lock(); defer { collected = nil; lock.unlock() }; return collected ?? [] }

    private func acceptLoop(_ s: Int32) {
        while true {
            let client = accept(s, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return  // The socket closed.
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        Self.noSigPipe(client)
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
        Self.setTimeout(client, seconds: Self.readSeconds)
        let reply: ControlReply
        if let line = Self.readLine(client, max: Self.maxLine),
           let request = try? JSONDecoder().decode(ControlRequest.self, from: line) {
            let peerIsEarshot = Self.peerIsThisProgram(client)
            let done = DispatchSemaphore(value: 0)
            let box = ReplyBox()
            let handler = self.handler
            Task {
                box.value = await handler(request, peerIsEarshot)
                done.signal()
            }
            done.wait()
            reply = box.value ?? ControlReply(ok: false, lines: ["no reply"])
        } else {
            reply = ControlReply(ok: false, lines: ["the request is not a valid line"])
        }
        guard var data = try? JSONEncoder().encode(reply) else { return }
        data.append(0x0A)
        Self.writeAll(client, data)
    }

    private final class ReplyBox: @unchecked Sendable { var value: ControlReply? }

    // MARK: - Client (the command line)

    /// Sends one request to the running app. Nil if no app listens, or no reply came in `timeout` seconds.
    static func send(_ request: ControlRequest, path: String, timeout: Int) -> ControlReply? {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        defer { close(s) }
        noSigPipe(s)
        guard var addr = address(path) else { return nil }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0, var data = try? JSONEncoder().encode(request) else { return nil }
        data.append(0x0A)
        guard writeAll(s, data) else { return nil }
        setTimeout(s, seconds: timeout)
        guard let line = readLine(s, max: 4 * 1024 * 1024) else { return nil }
        return try? JSONDecoder().decode(ControlReply.self, from: line)
    }

    // MARK: - Socket helpers

    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }

    static func noSigPipe(_ s: Int32) {
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setTimeout(_ s: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Reads up to the first new line. Nil on an error, a timeout or a line longer than `max`.
    static func readLine(_ s: Int32, max: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= max {
            let n = read(s, &buffer, buffer.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return nil }
            data.append(contentsOf: buffer[0..<n])
            if let end = data.firstIndex(of: 0x0A) { return Data(data[data.startIndex..<end]) }
        }
        return nil
    }

    @discardableResult
    static func writeAll(_ s: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var sent = 0
            while sent < raw.count {
                let n = write(s, raw.baseAddress! + sent, raw.count - sent)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { return false }
                sent += n
            }
            return true
        }
    }

    // MARK: - Peer check

    /// SOL_LOCAL and LOCAL_PEERTOKEN from <sys/un.h>: the audit token of the peer of a Unix socket.
    private static let solLocal: Int32 = 0
    private static let localPeerToken: Int32 = 0x006

    /// The designated requirement of this program's code signature. The command line is this same program.
    private static let ownRequirement: SecRequirement? = {
        var me: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &me) == errSecSuccess, let me else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(me, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(), &requirement) == errSecSuccess else { return nil }
        return requirement
    }()

    /// True if the peer process has the code signature of this program.
    static func peerIsThisProgram(_ s: Int32) -> Bool {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(s, solLocal, localPeerToken, &token, &length) == 0 else { return false }
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guest) == errSecSuccess, let guest,
              let requirement = ownRequirement else { return false }
        return SecCodeCheckValidity(guest, SecCSFlags(), requirement) == errSecSuccess
    }
}
