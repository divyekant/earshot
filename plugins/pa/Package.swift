// swift-tools-version:6.0
// The PA plugin of earshot, phase 1 (docs/PLUGINS.md, docs/PA.md). A separate program: earshot starts it as a plugin.
// It is not a part of the app (R-PL-1). It uses only parts that macOS includes: SQLite, Foundation and EventKit.
// No network code. Phase 2 adds one prebuilt binary: llama.cpp, for the embedding model.
import PackageDescription

// The program has its own Info.plist in the linker section __TEXT,__info_plist, so that macOS can show the question
// for access to Reminders (probe 1, try A). install-pa.sh also puts the program in an app bundle (try B).
let infoPlist = Context.packageDirectory + "/Info.plist"

// Phase 2 (E10): llama.cpp runs the embedding candidates 3 and 4 (GGUF files). Prebuilt for Apple platforms, MIT.
// SwiftPM checks the SHA-256 sum of the file. The build on Linux has no model runtime (tests use the hash model).
#if os(macOS)
let llamaTargets: [Target] = [
    .binaryTarget(
        name: "llama",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b12284/llama-b12284-xcframework.zip",
        checksum: "3b503a596883441a7a6dcbf173a03a3332dfa5c098d2805c1dfda5157644c7e2"),
]
let macDependencies: [Target.Dependency] = ["PACore", "llama"]
#else
let llamaTargets: [Target] = []
let macDependencies: [Target.Dependency] = ["PACore"]
#endif

let package = Package(
    name: "earshot-pa",
    platforms: [.macOS("14.0")],
    products: [
        .executable(name: "earshot-pa", targets: ["earshot-pa"]),
    ],
    targets: [
        // The system SQLite (macOS includes it). The module map only names the header and the library.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        // All logic. Foundation and SQLite only.
        .target(name: "PACore", dependencies: ["CSQLite"], path: "Sources/PACore"),
        // The interfaces of macOS: EventKit, the date detector, the wake from sleep.
        .target(name: "PAMac", dependencies: macDependencies, path: "Sources/PAMac"),
        .executableTarget(
            name: "earshot-pa", dependencies: ["PACore", "PAMac"], path: "Sources/earshot-pa",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", infoPlist], .when(platforms: [.macOS])),
                // In EarshotPA.app, llama.framework is in Contents/Frameworks (install-pa.sh).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(name: "PACoreTests", dependencies: ["PACore", "PAMac"], path: "Tests/PACoreTests",
                    resources: [.copy("Fixtures")]),
        // Tests that start the built program and talk to it through pipes.
        .testTarget(name: "PAContractTests", dependencies: ["earshot-pa", "PACore"], path: "Tests/PAContractTests"),
    ] + llamaTargets,
    swiftLanguageModes: [.v5]
)
