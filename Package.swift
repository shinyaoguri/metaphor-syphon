// swift-tools-version: 5.10

import PackageDescription
import Foundation

// metaphor-syphon — Syphon output for metaphor, as an official plugin package.
//
// This package exists so that the metaphor root manifest can stay free of binary
// targets: SwiftPM downloads a remote `binaryTarget(url:)` for every consumer that
// resolves a package, even when no product that depends on it is used (metaphor#792,
// ADR-0014). The Syphon.xcframework therefore lives here, and only sketches that
// actually publish to Syphon pay for it.

// Local build of the framework (make setup / scripts/build-syphon.sh) wins over the
// release asset, so Syphon-Framework changes can be tested before they are released.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let localFrameworkPath = "Frameworks/Syphon.xcframework"
let useLocalSyphon = FileManager.default.fileExists(atPath: packageDir + "/" + localFrameworkPath)

// Same strict-concurrency spelling as metaphor (tools-version stays 5.10, so the
// diagnostics are warnings; CI builds with -warnings-as-errors).
#if compiler(>=6.0)
let strictConcurrency: [SwiftSetting] = [.enableUpcomingFeature("StrictConcurrency")]
#else
let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]
#endif

// The release workflow rewrites the url + checksum below to this repository's own
// Release asset on every release (self-pin). Before the first release the pin
// borrows metaphor's v0.11.0 asset, which was built from the same Syphon-Framework
// commit (71351d4) with the same scripts/build-syphon.sh.
let syphonTarget: Target = useLocalSyphon
    ? .binaryTarget(name: "Syphon", path: localFrameworkPath)
    : .binaryTarget(
        name: "Syphon",
        url: "https://github.com/shinyaoguri/metaphor-syphon/releases/download/v0.1.1/Syphon.xcframework.zip",
        checksum: "0adef869457e34137cbb197b56071e6945e1246642241616c5bafba3301e14d0"
    )

let package = Package(
    name: "metaphor-syphon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MetaphorSyphon", targets: ["MetaphorSyphon"]),
    ],
    dependencies: [
        // Only the Core product is used. The upper bound is deliberate: while this package
        // still reads the deprecated `SketchConfig.syphon` / `syphonName` /
        // `SketchWindowConfig.syphonName` (the migration window, see SyphonOutputProvider.swift),
        // a metaphor minor that removes them (metaphor#1042) must not be picked up by
        // consumers that resolve `from:` ranges — SwiftPM does not treat 0.x minors as
        // breaking. Each metaphor minor gets a metaphor-syphon release that raises this
        // bound (docs/releasing.md); once the window is gone it can go back to `from:`.
        .package(url: "https://github.com/shinyaoguri/metaphor.git", "0.12.0"..<"0.13.0"),
    ],
    targets: [
        syphonTarget,
        // C bootstrap: an __attribute__((constructor)) that registers the output provider
        // at load, so `import MetaphorSyphon` + `plugins: [.syphon()]` needs no enable() call.
        .target(name: "CMetaphorSyphonBootstrap"),
        .target(
            name: "MetaphorSyphon",
            dependencies: [
                .product(name: "MetaphorCore", package: "metaphor"),
                "Syphon",
                "CMetaphorSyphonBootstrap",
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "MetaphorSyphonTests",
            dependencies: [
                "MetaphorSyphon",
                .product(name: "MetaphorCore", package: "metaphor"),
            ],
            swiftSettings: strictConcurrency
        ),
    ]
)
