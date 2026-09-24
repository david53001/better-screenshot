import TestKit

// Aggregate every test array in this target here. New test files add their
// `[TestCase]` array to this concatenation.
runTests("EditorKitTests",
    rgbaColorTests + editorDocumentTests + shapeAnnotationTests + arrowGeometryTests + textAnnotationTests + counterAnnotationTests + redactorTests + documentRendererTests + cropTests + annotationStyleCodableTests + editorBoundsClampTests + textChipTests + textFontTests + opacityTests + inspectorModelTests + zoomMathTests + canvasStyleEditTests + redactionTests + highlighterTests + spotlightTests
    + textScaleTests + textStyleTests + textRenderTests
)
