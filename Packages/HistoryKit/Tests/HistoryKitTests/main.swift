import TestKit

// Aggregate every test array in this target here. New test files add their
// `[TestCase]` array to this concatenation.
runTests("HistoryKitTests",
    historyIndexTests +
    restoreStackTests +
    thumbnailRendererTests +
    historyStoreTests +
    historySelectionTests +
    historyEmptyStateTests
)
