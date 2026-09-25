import TestKit
@testable import TourKit

let catalogShapeTests: [TestCase] = [
    TestCase("everyTourIdHasExactlyOneTour") { t in
        t.equal(Set(TourCatalog.all.map(\.id)), Set(TourID.allCases))
        t.equal(TourCatalog.all.count, TourID.allCases.count)
    },
    TestCase("handOversPointAtRealTours") { t in
        for tour in TourCatalog.all {
            if let next = tour.handsOverTo { t.isTrue(next != tour.id, "\(tour.id) hands over to itself") }
        }
    },
]
