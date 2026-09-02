// swift-tools-version:5.9
import PackageDescription

// No external dependencies on purpose. A lint-adjacent tool that runs in a
// build phase should not drag a dependency graph through resolution on every
// clean checkout, and it keeps `swift build` fast for contributors.
let package = Package(
    name: "xcprune",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "xcprune", targets: ["xcprune"]),
        .library(name: "XCPruneKit", targets: ["XCPruneKit"]),
    ],
    targets: [
        .target(name: "XCPruneKit"),
        .executableTarget(name: "xcprune", dependencies: ["XCPruneKit"]),
        .testTarget(name: "XCPruneKitTests", dependencies: ["XCPruneKit"]),
    ]
)
