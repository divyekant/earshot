@testable import EarshotApp
import EarshotCore
import XCTest

/// The control socket: one request line, one reply line, same user only (R-CT-2).
final class ControlSocketTests: XCTestCase {
    /// A short path: a Unix socket path has at most 103 bytes.
    private let path = "/tmp/es-\(UUID().uuidString.prefix(8)).sock"

    func testRequestAndReply() throws {
        let server = ControlServer(path: path) { request, _ in
            ControlReply(ok: true, lines: ["got \(request.cmd) \(request.text ?? "")"])
        }
        try server.start()
        defer { server.stop() }
        let reply = ControlServer.send(ControlRequest(cmd: "run", text: "open notes"), path: path, timeout: 5)
        XCTAssertEqual(reply, ControlReply(ok: true, lines: ["got run open notes"]))
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testNoServerGivesNil() {
        XCTAssertNil(ControlServer.send(ControlRequest(cmd: "status"), path: path, timeout: 1))
    }

    func testCollectsAnswersOnlyWhileARunWaits() {
        let server = ControlServer(path: path) { _, _ in ControlReply(ok: true, lines: []) }
        server.collect("lost")
        server.startCollecting()
        server.collect("Helper: saved")
        XCTAssertEqual(server.collectedCount, 1)
        XCTAssertEqual(server.stopCollecting(), ["Helper: saved"])
        XCTAssertEqual(server.collectedCount, 0)
    }
}
