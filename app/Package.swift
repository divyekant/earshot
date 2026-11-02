// swift-tools-version:6.0
// earshot app. The probe (../probe) stays as the lab for experiments.
// Modules talk only through the protocols in EarshotCore, so that each module can change alone.
// Language mode: Swift 5 (see docs/BUILD-PLAN.md), so that strict concurrency does not slow the threads.
import PackageDescription

let package = Package(
    name: "earshot",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "earshot", targets: ["EarshotApp"]),
        .library(name: "EarshotCore", targets: ["EarshotCore"]),
    ],
    targets: [
        .target(name: "EarshotCore", path: "Sources/EarshotCore"),
        .executableTarget(name: "EarshotApp", dependencies: ["EarshotCore"], path: "Sources/EarshotApp"),
        .testTarget(name: "EarshotCoreTests", dependencies: ["EarshotCore"], path: "Tests/EarshotCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
