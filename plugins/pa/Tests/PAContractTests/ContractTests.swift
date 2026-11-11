import Foundation
import XCTest

/// Tests that start the built program and talk to it through pipes, as earshot does (docs/PLUGINS.md, section 5).
final class ContractTests: XCTestCase {
    /// The built program, next to the test bundle.
    static var program: URL {
        var dir = Bundle(for: ContractTests.self).bundleURL
        while dir.pathExtension == "xctest" || !FileManager.default.fileExists(atPath: dir.appendingPathComponent("earshot-pa").path) {
            let up = dir.deletingLastPathComponent()
            if up == dir { break }
            dir = up
        }
        return dir.appendingPathComponent("earshot-pa")
    }

    final class Plugin {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let folder: URL
        private var buffer = Data()
        private let lock = NSLock()
        private var lines: [[String: Any]] = []

        init(folder: URL? = nil) throws {
            self.folder = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent("pa-contract-\(UUID().uuidString)")
            process.executableURL = ContractTests.program
            // The same environment as earshot gives: nothing else.
            process.environment = ["EARSHOT_PLUGIN_DATA": self.folder.path, "EARSHOT_CONTRACT": "1",
                                   "PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_GB.UTF-8",
                                   "TMPDIR": NSTemporaryDirectory()]
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
                guard let self else { return }
                let d = h.availableData
                self.lock.lock()
                self.buffer.append(d)
                while let nl = self.buffer.firstIndex(of: 0x0A) {
                    let line = self.buffer.subdata(in: self.buffer.startIndex..<nl)
                    self.buffer.removeSubrange(self.buffer.startIndex...nl)
                    if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { self.lines.append(obj) }
                }
                self.lock.unlock()
            }
            try process.run()
        }

        func send(_ s: String) { stdin.fileHandleForWriting.write(Data((s + "\n").utf8)) }

        func send(_ obj: [String: Any]) {
            let d = try! JSONSerialization.data(withJSONObject: obj)
            stdin.fileHandleForWriting.write(d + Data([0x0A]))
        }

        /// Waits for an answer with this `re`.
        func answer(_ re: String, timeout: TimeInterval = 5) -> [String: Any]? {
            let end = Date().addingTimeInterval(timeout)
            while Date() < end {
                lock.lock()
                if let i = lines.firstIndex(where: { $0["re"] as? String == re }) {
                    let a = lines.remove(at: i)
                    lock.unlock()
                    return a
                }
                lock.unlock()
                usleep(1000)
            }
            return nil
        }

        func all() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return lines }

        /// Closes stdin and gives the time until the program stopped.
        func close(timeout: TimeInterval = 5) -> TimeInterval? {
            let start = Date()
            try? stdin.fileHandleForWriting.close()
            while process.isRunning && Date().timeIntervalSince(start) < timeout { usleep(2000) }
            return process.isRunning ? nil : Date().timeIntervalSince(start)
        }

        deinit { if process.isRunning { process.terminate() } }
    }

    func testHelloCommandAndStop() throws {
        let p = try Plugin()
        p.send(["type": "hello", "contract": 1])
        p.send(["type": "command", "id": "a1", "lead": "what is due", "text": "", "context": [:]])
        let a = p.answer("a1")
        XCTAssertNotNil(a)
        XCTAssertEqual(a?["type"] as? String, "answer")
        let stopped = p.close()
        XCTAssertNotNil(stopped, "The program did not stop after stdin closed.")
        print("CONTRACT stop after stdin closed: \(Int((stopped ?? 99) * 1000)) ms")
        XCTAssertLessThan(stopped ?? 99, 1.0)
    }

    func testOddInputDoesNotStopTheProgram() throws {
        let p = try Plugin()
        p.send(["type": "hello", "contract": 1])
        p.send("this is not json")
        p.send(#"{"type":"unknown-type"}"#)
        p.send(["type": "command", "id": "z1", "lead": "sing", "text": "x", "context": [:]])
        p.send(["type": "command", "id": "z2", "lead": "note", "text": String(repeating: "ä😀\"\\", count: 2500), "context": [:]])
        XCTAssertNotNil(p.answer("z1"))
        XCTAssertNotNil(p.answer("z2"))
        XCTAssertTrue(p.process.isRunning)
        XCTAssertNotNil(p.close())
    }
}
