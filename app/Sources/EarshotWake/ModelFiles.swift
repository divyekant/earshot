import CryptoKit
import Foundation

/// One file of a model pack, with its size and SHA-256 sum.
struct ModelFile: Sendable, Equatable {
    let path: String
    let size: Int
    let sha256: String
}

/// The model files from one Hugging Face repository, at a fixed revision.
/// earshot downloads them once, checks each SHA-256 sum, and then reads them from the store folder.
/// The download sends no audio and no text (R-MD-1). It is the only network use of always-on mode.
public struct ModelPack: Sendable, Equatable {
    public let name: String
    let repo: String
    let revision: String
    let files: [ModelFile]

    /// The sum of the file sizes, in bytes.
    public var totalBytes: Int { files.reduce(0) { $0 + $1.size } }

    /// `<store>/models/<name>-<first 7 characters of the revision>/`.
    public func folder(in store: URL) -> URL {
        store.appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("\(name)-\(revision.prefix(7))", isDirectory: true)
    }

    static let markerName = ".verified"

    /// True if all files are in the folder, with the right sizes, and the folder has the check marker.
    public func isReady(in store: URL) -> Bool {
        let folder = folder(in: store)
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent(Self.markerName).path) else { return false }
        for file in files {
            let path = folder.appendingPathComponent(file.path).path
            guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber, size.intValue == file.size
            else { return false }
        }
        return true
    }

    func url(of file: ModelFile) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.path)")!
    }

    /// Makes sure that the files are in the store folder. Downloads and checks the missing files.
    /// - Parameter progress: the part done, 0 to 1. It is called on a background queue.
    /// - Returns: the folder.
    @discardableResult
    public func ensure(in store: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let folder = folder(in: store)
        if isReady(in: store) { progress?(1); return folder }
        let fm = FileManager.default
        // Download into a work folder. Move it into place only when all files are good,
        // so that a stopped download never leaves a half pack that looks ready.
        let work = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".partial",
                                                                             isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var done = 0
        let total = max(1, totalBytes)
        for file in files {
            let target = work.appendingPathComponent(file.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (temporary, response) = try await session.download(from: url(of: file))
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw WakeError("The download of \(name)/\(file.path) failed: HTTP \(http.statusCode).")
            }
            try Self.check(temporary, against: file, pack: name)
            try fm.moveItem(at: temporary, to: target)
            done += file.size
            progress?(Double(done) / Double(total))
        }
        try Data("\(repo)@\(revision)\n".utf8).write(to: work.appendingPathComponent(Self.markerName))
        try? fm.removeItem(at: folder)
        try fm.moveItem(at: work, to: folder)
        return folder
    }

    /// Checks the size and the SHA-256 sum of a downloaded file.
    static func check(_ url: URL, against file: ModelFile, pack: String) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count == file.size else {
            throw WakeError("\(pack)/\(file.path) has \(data.count) bytes. It must have \(file.size) bytes.")
        }
        let sum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard sum == file.sha256 else {
            throw WakeError("\(pack)/\(file.path) has the wrong SHA-256 sum. earshot does not use it.")
        }
    }
}

/// An error of the wake phrase models, with a text for the management window.
public struct WakeError: Error, LocalizedError, CustomStringConvertible, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
    public var description: String { message }
}

/// The two model packs of always-on mode (R-ON-1, R-ON-3, D-11).
public enum WakeModelPacks {
    /// The keyword spotter: icefall KWS Zipformer (gigaspeech, 3.49M parameters, Apache-2.0), Core ML INT8.
    public static let spotter = ModelPack(
        name: "kws-zipformer-3m",
        repo: "aufklarer/KWS-Zipformer-3M-CoreML-INT8",
        revision: "45929a20b1d7d9332ee137952b7ff4200eeb72a8",
        files: [
            ModelFile(path: "bpe.model", size: 244837,
                      sha256: "c8a2a0129c4ab8e463164c142f82d25649661b122c8cd0b7aab5c9e80b90ad24"),
            ModelFile(path: "config.json", size: 3876,
                      sha256: "bd5b6a82a7e2a4e1a7b62a33def41842b57456aa86087b3e7a6bb4623b004976"),
            ModelFile(path: "decoder.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "e9da670c9bcb826ebfaaaef5cdee546879d82aee4bc3602bfaa225b4c8824069"),
            ModelFile(path: "decoder.mlmodelc/coremldata.bin", size: 311,
                      sha256: "238b9068482758e8b9f4f5109e2718464923cb5074800473cf22641270f09104"),
            ModelFile(path: "decoder.mlmodelc/model.mil", size: 6590,
                      sha256: "fcf1c0daf38ad4496068fce26c65abfa562250eff29be6a612ebc0125d4899ee"),
            ModelFile(path: "decoder.mlmodelc/weights/weight.bin", size: 530880,
                      sha256: "d73e5d5e1cee395728d2e4c481b32c524f14d2325419691f7850e60815d260ce"),
            ModelFile(path: "encoder.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "ae2f7d2db71e650218357dd8a50133d7bc34ea48d393e84e36919d9a484dfa87"),
            ModelFile(path: "encoder.mlmodelc/coremldata.bin", size: 3123,
                      sha256: "6eeb1ed89a7fd466d3a7e358a890ba149c8ab921d4d12e458552c1a35b405bb0"),
            ModelFile(path: "encoder.mlmodelc/model.mil", size: 531386,
                      sha256: "b1721f4756e0b78cd116297a5fd1dec9f92b521107e96ff23820e699f30d63a3"),
            ModelFile(path: "encoder.mlmodelc/weights/weight.bin", size: 2930688,
                      sha256: "2de84c14f8d401dd8d66e1884e81703576a61ea10da0a99f8991ff9f1d4feedb"),
            ModelFile(path: "joiner.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "779ec8cb7c61d6c79a8e0d784624ecd61cdd2943504adc5c2113b13f31114db3"),
            ModelFile(path: "joiner.mlmodelc/coremldata.bin", size: 345,
                      sha256: "18283b3e99d8aa63f0f3910cf2a93bac0e5a890b944122a29e3672b9031d6dfd"),
            ModelFile(path: "joiner.mlmodelc/model.mil", size: 1495,
                      sha256: "8c8869b26d177622e6d6979fc19064f1cebb0d32d7ce953465ed9ca9dc3df169"),
            ModelFile(path: "joiner.mlmodelc/weights/weight.bin", size: 161768,
                      sha256: "8dbef96b74ca6ae09e3b5f2d3f73d429d244194c7a2627f750816e564b206004"),
            ModelFile(path: "tokens.txt", size: 5006,
                      sha256: "fd2ded4050a55d2b1578870ba8697d02371980217806b7558bd0a5cc60f3ba53"),
        ]
    )

    /// The voice model: WeSpeaker ResNet34-LM (VoxCeleb), Core ML. 256-value speaker embeddings.
    public static let voice = ModelPack(
        name: "wespeaker-resnet34-lm",
        repo: "aufklarer/WeSpeaker-ResNet34-LM-CoreML",
        revision: "b358f33f9e268a15aaf4aae0d4e747b82a8499e6",
        files: [
            ModelFile(path: "wespeaker.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "f22f984e4419ebc6682dbe6a2ce990c876144eb6e43e9e4843b92917bdcd5ba7"),
            ModelFile(path: "wespeaker.mlmodelc/coremldata.bin", size: 452,
                      sha256: "bf152705e26efe04fac84bc332c395443d4b5c4cc1b2891ffd5e274e53b365b2"),
            ModelFile(path: "wespeaker.mlmodelc/metadata.json", size: 2402,
                      sha256: "885d8e956a649e79a099e35acf367021c86091e321ebef26e2ad9d89c3ff757f"),
            ModelFile(path: "wespeaker.mlmodelc/model.mil", size: 71134,
                      sha256: "e1f3d6188067607d5e91aa5004aeffb35c9f367b85628eff2e87c59ac5c379f2"),
            ModelFile(path: "wespeaker.mlmodelc/weights/weight.bin", size: 13264960,
                      sha256: "6dba18a57a81b1e872802ca4def29541bb7900ccff430d9b2040092cadd7d688"),
        ]
    )

    /// The turn model: Pipecat Smart Turn v3.2 (BSD-2-Clause, about 8M parameters), Core ML (R-ON-1, I-2).
    /// It is optional: if it does not download or load, the end silence alone ends a turn.
    public static let turn = ModelPack(
        name: "smart-turn-v3.2",
        repo: "aufklarer/Smart-Turn-v3.2-CoreML",
        revision: "75f069717f500947195fa1945c46ddb472559cff",
        files: [
            ModelFile(path: "config.json", size: 1029,
                      sha256: "bc09d1b40285465b389dc42cef54290fa1db7b4928348018bc61d819b4914402"),
            ModelFile(path: "smart_turn.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "1646746d0029e78d26be065e62602d4f89e51013ec238b653adf7d7d21057f89"),
            ModelFile(path: "smart_turn.mlmodelc/coremldata.bin", size: 643,
                      sha256: "9245ac99889c9d738cba6c89da9e851fd16488bf8effbc15a109d06b401c9383"),
            ModelFile(path: "smart_turn.mlmodelc/model.mil", size: 69968,
                      sha256: "41a6d9ac0f7d01d738e56ecdf4435e55f139591541b7cf1a4dba6b9ce2f1c9ef"),
            ModelFile(path: "smart_turn.mlmodelc/weights/weight.bin", size: 16714240,
                      sha256: "b6295316741a0149e1fcab7cdf030e1b9bfb0eef778207accee91a2a9703a39c"),
        ]
    )

    /// The packs that always-on mode needs. The turn model is extra (`turn`).
    public static let all = [spotter, voice]

    /// The sum of the download sizes of the needed packs, in bytes (about 17.7 MB).
    public static var totalBytes: Int { all.reduce(0) { $0 + $1.totalBytes } }
}
