import XCTest

final class RowDensityTests: XCTestCase {
    func testMigrationFromCompactRows() {
        XCTAssertEqual(RowDensity.migrating(fromCompactRows: true), .compact)
        XCTAssertEqual(RowDensity.migrating(fromCompactRows: false), .comfortable)
        XCTAssertEqual(RowDensity.migrating(fromCompactRows: nil), .comfortable)
    }

    func testLargeGrowsBeyondComfortable() {
        XCTAssertGreaterThan(RowDensity.large.listRowHeight, RowDensity.comfortable.listRowHeight)
        XCTAssertGreaterThan(RowDensity.large.verticalPadding, RowDensity.comfortable.verticalPadding)
        XCTAssertGreaterThan(RowDensity.large.titleLineLimit, RowDensity.comfortable.titleLineLimit)
        XCTAssertGreaterThan(RowDensity.comfortable.listRowHeight, RowDensity.compact.listRowHeight)
    }
}
