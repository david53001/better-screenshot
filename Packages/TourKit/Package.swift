// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TourKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TourKit", targets: ["TourKit"])],
    dependencies: [.package(path: "../TestKit"), .package(path: "../DesignKit")],
    targets: [
        .target(name: "TourKit", dependencies: [.product(name: "DesignKit", package: "DesignKit")]),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/TourKit TourKitTests
        .executableTarget(
            name: "TourKitTests",
            dependencies: ["TourKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/TourKitTests"
        ),
    ]
)
