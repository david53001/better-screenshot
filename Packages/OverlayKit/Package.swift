// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OverlayKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OverlayKit", targets: ["OverlayKit"])],
    dependencies: [.package(path: "../TestKit"), .package(path: "../CaptureKit"), .package(path: "../TourKit")],
    targets: [
        .target(name: "OverlayKit", dependencies: [.product(name: "CaptureKit", package: "CaptureKit"),
                                                .product(name: "TourKit", package: "TourKit")]),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/OverlayKit OverlayKitTests
        .executableTarget(
            name: "OverlayKitTests",
            dependencies: ["OverlayKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/OverlayKitTests"
        ),
    ]
)
