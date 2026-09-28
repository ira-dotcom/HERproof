// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HerProof",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HerProofKit", targets: ["HerProofKit"]),
        .library(name: "HerProofUI", targets: ["HerProofUI"]),
    ],
    targets: [
        .target(name: "HerProofKit"),
        .target(name: "HerProofUI", dependencies: ["HerProofKit"]),
        .testTarget(name: "HerProofKitTests", dependencies: ["HerProofKit"]),
    ]
)
