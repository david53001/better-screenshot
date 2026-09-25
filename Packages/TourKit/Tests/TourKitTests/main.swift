import TestKit

// Aggregate every test array in this target here. New test files add their
// `[TestCase]` array to this concatenation.
runTests("TourKitTests",
    catalogShapeTests
    + catalogLintTests
    + tourAudienceTests
    + tourRulesTests
    + tourEngineTests
    + tagLayoutTests + tagKeysTests + tagStyleTests
    + tagFitTests
)
