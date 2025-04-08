// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RomPatcherSwift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .executable(
            name: "rom-patcher",
            targets: ["rom-patcher"]
        ),
        .library(
            name: "BinFile",
            type: .dynamic,
            targets: ["BinFile"]
        ),
        .library(
            name: "RomPatcherCore",
            type: .dynamic,
            targets: ["RomPatcherCore"]
        )
    ],
    targets: [
        .executableTarget(
            name: "rom-patcher",
            dependencies: ["BinFile", "RomPatcherCore"],
            path: "Sources/rom-patcher"
        ),
        .target(
            name: "BinFile",
            path: "Sources/BinFile"
        ),
        .target(
            name: "RomPatcherCore",
            dependencies: ["BinFile"],
            path: "Sources/RomPatcherCore"
        )
    ]
)
