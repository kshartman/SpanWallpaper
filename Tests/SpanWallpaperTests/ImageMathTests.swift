import XCTest
@testable import SpanWallpaperLib

final class ImageMathTests: XCTestCase {

    private func assertRect(_ r: CGRect, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                            accuracy: CGFloat = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.origin.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(r.origin.y, y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(r.width, w, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(r.height, h, accuracy: accuracy, file: file, line: line)
    }

    func testLandscapeSourceOnLandscapeCanvas() {
        // 4000x2000 source (2:1) on 3840x1080 canvas (3.56:1) — source is less wide, crop height
        let r = ImageMath.sourceFillRect(sourceSize: CGSize(width: 4000, height: 2000),
                                         canvas: CGSize(width: 3840, height: 1080))
        XCTAssertEqual(r.origin.x, 0, accuracy: 0.001)
        let expectedH = 4000.0 / (3840.0 / 1080.0)
        XCTAssertEqual(r.height, expectedH, accuracy: 0.001)
        XCTAssertEqual(r.width, 4000, accuracy: 0.001)
    }

    func testPortraitSourceOnLandscapeCanvas() {
        // 2000x4000 source (0.5:1) on 3840x1080 canvas (3.56:1) — crop height
        let r = ImageMath.sourceFillRect(sourceSize: CGSize(width: 2000, height: 4000),
                                         canvas: CGSize(width: 3840, height: 1080))
        XCTAssertEqual(r.width, 2000, accuracy: 0.001)
        let expectedH = 2000.0 / (3840.0 / 1080.0)
        XCTAssertEqual(r.height, expectedH, accuracy: 0.001)
    }

    func testSquareSourceOnRectangularCanvas() {
        // 1000x1000 (1:1) on 1920x1080 (1.78:1) — crop height
        let r = ImageMath.sourceFillRect(sourceSize: CGSize(width: 1000, height: 1000),
                                         canvas: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(r.width, 1000, accuracy: 0.001)
        let expectedH = 1000.0 / (1920.0 / 1080.0)
        assertRect(r, x: 0, y: (1000.0 - expectedH) / 2.0, w: 1000, h: expectedH)
    }

    func testExactAspectMatch() {
        // Same aspect ratio — no crop needed, full source used
        let r = ImageMath.sourceFillRect(sourceSize: CGSize(width: 1920, height: 1080),
                                         canvas: CGSize(width: 3840, height: 2160))
        assertRect(r, x: 0, y: 0, w: 1920, h: 1080)
    }

    func testWidePanorama() {
        // 10000x1000 (10:1) on 1920x1080 (1.78:1) — source much wider, crop width
        let r = ImageMath.sourceFillRect(sourceSize: CGSize(width: 10000, height: 1000),
                                         canvas: CGSize(width: 1920, height: 1080))
        let expectedW = 1000.0 * (1920.0 / 1080.0)
        XCTAssertEqual(r.width, expectedW, accuracy: 0.001)
        XCTAssertEqual(r.height, 1000, accuracy: 0.001)
        XCTAssertEqual(r.origin.x, (10000.0 - expectedW) / 2.0, accuracy: 0.001)
    }

    func testZeroDimensionDoesNotCrash() {
        let r1 = ImageMath.sourceFillRect(sourceSize: CGSize(width: 0, height: 1000),
                                          canvas: CGSize(width: 1920, height: 1080))
        XCTAssertFalse(r1.width.isNaN && r1.height.isNaN, "Should produce a finite rect or zero, not crash")

        let r2 = ImageMath.sourceFillRect(sourceSize: CGSize(width: 1000, height: 0),
                                          canvas: CGSize(width: 1920, height: 1080))
        XCTAssertFalse(r2.width.isNaN && r2.height.isNaN)
    }
}
