// swift-tools-version:5.10
// earshot E0 probe. See docs/experiments/E0-viability.md.
import Foundation
import PackageDescription

// The linker embeds Support/Info.plist in the binary.
// macOS reads the microphone and speech usage text from it.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist")
    .path

let package = Package(
    name: "earshot-probe",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "earshot-probe",
            path: "Sources/EarshotProbe",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
    ]
)
