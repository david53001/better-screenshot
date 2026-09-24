import TestKit

runTests("RecordingKitTests",
    recorderStateTests + recordingConfigTests + pauseTimelineTests + trimRangeTests + trimExporterTests + silenceFillTests + letterboxFitTests
        + deviceChoiceTests + micLevelTests
)
