// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ocr-bench",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/CaptureKit"),
    ],
    targets: [
        .executableTarget(
            name: "ocr-bench",
            dependencies: [.product(name: "CaptureKit", package: "CaptureKit")]
        ),
    ]
)
