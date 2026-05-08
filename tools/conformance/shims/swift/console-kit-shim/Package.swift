// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ConsoleKitShim",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        // Path-dep on the bundled reference-framework copy of Vapor's console-kit.
        // SPM will resolve console-kit's transitive deps (swift-log, swift-nio) from
        // the registry; that's intentional — pinning all transitive sources locally
        // would 10x the repo size for marginal gain.
        .package(name: "console-kit", path: "../../../../../reference-frameworks/console-kit"),
    ],
    targets: [
        .executableTarget(
            name: "ConsoleKitShim",
            dependencies: [
                .product(name: "ConsoleKitTerminal", package: "console-kit"),
            ]
        ),
    ]
)
