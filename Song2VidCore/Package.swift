// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Song2VidCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Song2VidCore", targets: ["Song2VidCore"]),
    ],
    targets: [
        .target(name: "Song2VidCore"),
        .testTarget(name: "Song2VidCoreTests", dependencies: ["Song2VidCore"]),
    ]
)
