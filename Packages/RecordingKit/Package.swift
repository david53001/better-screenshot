// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RecordingKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RecordingKit", targets: ["RecordingKit"])],
    dependencies: [.package(path: "../TestKit"), .package(path: "../TourKit")],
    targets: [
        .target(name: "RecordingKit", dependencies: [.product(name: "TourKit", package: "TourKit")]),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/RecordingKit RecordingKitTests
        .executableTarget(
            name: "RecordingKitTests",
            dependencies: ["RecordingKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/RecordingKitTests"
        ),
    ]
)
