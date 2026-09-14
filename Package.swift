// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PalmRelay",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "RelayCore", targets: ["RelayCore"])],
    targets: [
        .target(name: "RelayCore"),
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"])
    ]
)
