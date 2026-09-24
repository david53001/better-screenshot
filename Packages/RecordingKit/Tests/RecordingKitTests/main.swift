import TestKit

runTests("RecordingKitTests",
    recorderStateTests + recordingConfigTests + pauseTimelineTests + trimRangeTests + cutListTests
        + trimExporterTests
)
