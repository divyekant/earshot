// swift-tools-version:6.0
// The PA plugin of earshot, phase 1 (docs/PLUGINS.md, docs/PA.md). A separate program: earshot starts it as a plugin.
// It is not a part of the app (R-PL-1). It uses only parts that macOS includes: SQLite, Foundation and EventKit.
// No model, no network code and no package dependency.
import PackageDescription

// The program has its own Info.plist in the linker section __TEXT,__info_plist, so that macOS can show the question
// for access to Reminders (probe 1, try A). install-pa.sh also puts the program in an app bundle (try B).
let infoPlist = Context.packageDirectory + "/Info.plist"

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
        .target(name: "PAMac", dependencies: ["PACore"], path: "Sources/PAMac"),
        .executableTarget(
            name: "earshot-pa", dependencies: ["PACore", "PAMac"], path: "Sources/earshot-pa",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", infoPlist], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(name: "PACoreTests", dependencies: ["PACore", "PAMac"], path: "Tests/PACoreTests",
                    resources: [.copy("Fixtures")]),
        // Tests that start the built program and talk to it through pipes.
        .testTarget(name: "PAContractTests", dependencies: ["earshot-pa", "PACore"], path: "Tests/PAContractTests"),
    ],
    swiftLanguageModes: [.v5]
)
