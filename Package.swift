// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyShot",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TinyShot", targets: ["TinyShot"])],
    targets: [
        .executableTarget(name: "TinyShot"),
        .testTarget(name: "TinyShotTests", dependencies: ["TinyShot"])
    ]
)
