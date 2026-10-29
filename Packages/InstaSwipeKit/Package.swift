// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "InstaSwipeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InstaSwipeKit", targets: ["InstaSwipeKit"])
    ],
    targets: [
        .target(name: "InstaSwipeKit"),
        .testTarget(name: "InstaSwipeKitTests", dependencies: ["InstaSwipeKit"])
    ]
)
