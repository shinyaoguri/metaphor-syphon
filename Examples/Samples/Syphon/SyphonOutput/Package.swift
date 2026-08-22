// swift-tools-version: 5.10
import PackageDescription

// metaphor-syphon の example。metaphor-syphon はこのリポジトリ（path）、metaphor 本体は
// Release タグ（url）から取る。自分のスケッチでは両方を url にする（README 参照）。
let package = Package(
    name: "SyphonOutput",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor-syphon", path: "../../../.."),
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "SyphonOutput",
            dependencies: [
                .product(name: "MetaphorCore", package: "metaphor"),
                .product(name: "MetaphorSyphon", package: "metaphor-syphon"),
            ],
            path: "SyphonOutput"
        ),
    ]
)
