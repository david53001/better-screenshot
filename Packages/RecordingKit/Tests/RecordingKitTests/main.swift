import TestKit

runTests("RecordingKitTests",
    recorderStateTests + recordingConfigTests + pauseTimelineTests + trimRangeTests + cutListTests
        + trimExporterTests + silenceFillTests + letterboxFitTests + deviceChoiceTests + micLevelTests
)
