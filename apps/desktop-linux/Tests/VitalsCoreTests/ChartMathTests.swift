import XCTest
@testable import VitalsCore

final class ChartMathTests: XCTestCase {

    func testReturnsInputWhenUnderLimit() {
        let xs = [1, 2, 3]
        XCTAssertEqual(ChartMath.downsample(xs, to: 10), xs)
    }

    func testThinsToExactCount() {
        let xs = Array(0..<1000)
        XCTAssertEqual(ChartMath.downsample(xs, to: 100).count, 100)
    }

    func testKeepsFirstAndLast() {
        let xs = Array(0..<500)
        let out = ChartMath.downsample(xs, to: 50)
        XCTAssertEqual(out.first, 0)
        XCTAssertEqual(out.last, 499)
    }

    func testNeverRepeatsWhenThinning() {
        let xs = Array(0..<300)
        let out = ChartMath.downsample(xs, to: 120)
        XCTAssertEqual(Set(out).count, out.count, "downsampled points must be distinct")
    }

    func testHandlesDegenerateLimits() {
        let xs = [10, 20, 30]
        XCTAssertEqual(ChartMath.downsample(xs, to: 1), xs, "maxCount <= 1 returns input unchanged")
        XCTAssertEqual(ChartMath.downsample([Int](), to: 5), [])
    }
}
