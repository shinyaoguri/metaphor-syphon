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
        url: "https://github.com/shinyaoguri/metaphor/releases/download/v0.11.0/Syphon.xcframework.zip",
        checksum: "bdc4b3accc697bd7a513e9341adb56ff8857d67390a11c8c806c7e5e0a255fa1"
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
        // Only the Core product is used: the provider / plugin API subset it relies on is
        // frozen from metaphor 0.12.0 on (metaphor#792 §5), so `from:` is safe within 0.x.
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.12.0"),
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
