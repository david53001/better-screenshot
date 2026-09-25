// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EditorKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EditorKit", targets: ["EditorKit"])],
    dependencies: [.package(path: "../TestKit"), .package(path: "../TourKit")],
    targets: [
        .target(name: "EditorKit", dependencies: [.product(name: "TourKit", package: "TourKit")]),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/EditorKit EditorKitTests
        .executableTarget(
            name: "EditorKitTests",
            dependencies: ["EditorKit", .product(name: "TestKit", package: "TestKit"),
                           .product(name: "TourKit", package: "TourKit")],
            path: "Tests/EditorKitTests"
        ),
    ]
)
