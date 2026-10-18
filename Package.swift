// swift-tools-version:5.9
import PackageDescription

// Root package: the BetterScreenshot menu-bar app executable.
// Build tooling note: the plans specify XcodeGen + xcodebuild, but only the
// macOS Command Line Tools are installed (no full Xcode), so the whole project
// is built with Swift Package Manager instead. The library modules remain the
// per-folder packages under Packages/ exactly as the plans lay them out; this
// root manifest adds the app executable (sources in App/) depending on them.
// The runnable .app bundle is assembled by scripts/build-app.sh.
let package = Package(
    name: "BetterScreenshot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "Packages/CaptureKit"),
        .package(path: "Packages/OverlayKit"),
        .package(path: "Packages/EditorKit"),
        .package(path: "Packages/RecordingKit"),
        .package(path: "Packages/HistoryKit"),
        .package(path: "Packages/TourKit"),
        .package(path: "Packages/DesignKit"),
        // Auto-updates (docs/sparkle-updates/README.md). Exact pin: the bundled framework,
        // the release tools in ~/Developer/Sparkle/2.10.0 and the appcast format must agree.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "BetterScreenshot",
            dependencies: [
                .product(name: "CaptureKit", package: "CaptureKit"),
                .product(name: "OverlayKit", package: "OverlayKit"),
                .product(name: "EditorKit", package: "EditorKit"),
                .product(name: "RecordingKit", package: "RecordingKit"),
                .product(name: "HistoryKit", package: "HistoryKit"),
                .product(name: "TourKit", package: "TourKit"),
                .product(name: "DesignKit", package: "DesignKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "App",
            exclude: ["Info.plist", "BetterScreenshot.entitlements"],
            // Sparkle.framework is embedded in BetterScreenshot.app/Contents/Frameworks by build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
