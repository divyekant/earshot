// swift-tools-version:5.10
// E2: Parakeet, with the model file of Hex, through transcribe.cpp.
// See docs/experiments/E2-web-and-speech.md, section 3.5.
// This is a separate package, so that the earshot probe keeps no third-party code.
import PackageDescription

let package = Package(
    name: "parakeet-ab",
    platforms: [.macOS(.v14)],
    targets: [
        // transcribe.cpp 0.3.1 (MIT), prebuilt for Apple platforms. SwiftPM checks the SHA-256 sum of the file.
        // The C module in the framework is CTranscribe.
        .binaryTarget(
            name: "TranscribeCpp",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.3.1/TranscribeCpp.xcframework.zip",
            checksum: "9fbd7fa74bf2cf903ee291d3fa98a02c5bd1cf07dda6adbc4f64c3a68be287ca"
        ),
        .executableTarget(
            name: "parakeet-ab",
            dependencies: ["TranscribeCpp"],
            path: "Sources/ParakeetAB",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
    ]
)
