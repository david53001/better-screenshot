import TestKit

// Aggregate every test array in this target here. New test files add their
// `[TestCase]` array to this concatenation.
runTests("CaptureKitTests",
    captureKitInfoTests +
    captureGeometryTests +
    imageCropperTests +
    imageEncoderTests +
    fileNamerTests +
    hotkeyComboTests +
    hotkeyBindingsTests +
    hotkeyActionTests +
    hotkeyCheatSheetTests +
    captureSettingsTests +
    overlayPositionerTests +
    tempImageWriterTests +
    recognitionResolverTests +
    textReflowTests +
    textRecognizerTests +
    windowPickingTests +
    overlayDismissScaleTests +
    tempFileRetentionScaleTests +
    selectionClampTests +
    focusRestoreTests
)
