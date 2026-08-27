import TestKit

// Aggregate every test array in this target here, like CaptureKitTests does.
runTests("OverlayKitTests", pinGeometryTests + quickAccessContrastTests + srgbTests + bandLuminanceTests)
