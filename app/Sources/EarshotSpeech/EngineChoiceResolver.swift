import EarshotCore
import Foundation

/// Finds the Parakeet model file. earshot reads the file in place. It never changes, moves or copies it (E2).
public struct ParakeetModelLocator {
    /// The model folder of Hex. Hex is a separate dictation app that keeps a Parakeet GGUF file here.
    public static var hexModelsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/hex/models")
    }

    public var folders: [URL]
    public var fileExists: (String) -> Bool
    public var listFiles: (URL) -> [String]

    public init(folders: [URL] = [ParakeetModelLocator.hexModelsFolder],
                fileExists: @escaping (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) },
                listFiles: @escaping (URL) -> [String] = ParakeetModelLocator.walk) {
        self.folders = folders; self.fileExists = fileExists; self.listFiles = listFiles
    }

    /// The model file to use, or nil.
    /// - If `configured` is not empty, only that file counts (the owner chose it).
    /// - Else the first Parakeet `.gguf` file in the folders, by name order.
    public func find(configured: String) -> String? {
        let path = (configured as NSString).expandingTildeInPath
        if !path.isEmpty { return fileExists(path) ? path : nil }
        for folder in folders {
            let names = listFiles(folder).filter(Self.isParakeetModel).sorted()
            for name in names {
                let full = folder.appendingPathComponent(name).path
                if fileExists(full) { return full }
            }
        }
        return nil
    }

    /// True for a file name such as "parakeet-unified-en-0.6b-Q8_0.gguf".
    public static func isParakeetModel(_ name: String) -> Bool {
        let n = (name as NSString).lastPathComponent.lowercased()
        return n.contains("parakeet") && n.hasSuffix(".gguf")
    }

    /// The relative paths of the files in a folder and its subfolders. Read only.
    public static func walk(_ folder: URL) -> [String] {
        guard let e = FileManager.default.enumerator(atPath: folder.path) else { return [] }
        var out: [String] = []
        while let f = e.nextObject() as? String { out.append(f) }
        return out
    }
}

/// The engine that the app runs, after "auto" is resolved.
public enum ResolvedEngine: Equatable, Sendable {
    case apple
    case parakeet(modelPath: String)

    public var id: String {
        switch self {
        case .apple: return AppleSpeechEngine.engineID
        case .parakeet: return ParakeetEngine.engineID
        }
    }
}

public enum EngineResolver {
    /// "auto": Apple. E2 (decision 6.2) chose Parakeet when its file exists, but the live test of 2026-11-02 changed it:
    /// with the memory of the Mac full, a Parakeet decode of a 1.5 s command took 0.2 s to 2 s (live up to 6.9 s),
    /// and Apple took about 30 ms. The Parakeet model also adds about 890 MB to a Mac that is short of memory.
    /// "parakeet" with no model file: Apple, with a reason, so that the owner can still give commands.
    public static func resolve(_ choice: EngineChoice, configuredModel: String,
                               locator: ParakeetModelLocator = ParakeetModelLocator()) -> (engine: ResolvedEngine, why: String) {
        switch choice {
        case .apple:
            return (.apple, "owner chose Apple")
        case .auto:
            return (.apple, "auto: Apple (Parakeet is slow when memory is short)")
        case .parakeet:
            if let path = locator.find(configured: configuredModel) {
                return (.parakeet(modelPath: path), "owner chose Parakeet")
            }
            let missing = configuredModel.isEmpty ? "no Parakeet model file in the Hex folder" : "Parakeet model file not found"
            return (.apple, "owner chose Parakeet, but \(missing); using Apple")
        }
    }
}
