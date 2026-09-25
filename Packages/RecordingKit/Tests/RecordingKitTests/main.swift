import TestKit

runTests("RecordingKitTests",
    recorderStateTests + recordingConfigTests + pauseTimelineTests + trimRangeTests + cutListTests
        + timeRulerTests + filmstripFramesTests + trimExporterTests + silenceFillTests + letterboxFitTests + deviceChoiceTests + micLevelTests
)
