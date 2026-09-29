// swift-tools-version:5.9
import PackageDescription

// The app's shared look (the MacStats native design language): tokens, the one
// dark HUD surface, continuous-corner helpers and SwiftUI card styles. No
// dependencies, so every other package can use it.
let package = Package(
    name: "DesignKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DesignKit", targets: ["DesignKit"])],
    dependencies: [.package(path: "../TestKit")],
    targets: [
        .target(name: "DesignKit"),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/DesignKit DesignKitTests
        .executableTarget(
            name: "DesignKitTests",
            dependencies: ["DesignKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/DesignKitTests"
        ),
    ]
)
