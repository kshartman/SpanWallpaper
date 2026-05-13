import XCTest
@testable import SpanWallpaperLib

final class FileCleanupTests: XCTestCase {

    func testRemovesOldSliceFiles() {
        XCTAssertTrue(SliceFileMatch.shouldClean(filename: "a1b2c3d4_12345.jpg", keeping: []))
        XCTAssertTrue(SliceFileMatch.shouldClean(filename: "DEADBEEF_0.jpg", keeping: []))
    }

    func testRemovesOrphanedTmpFiles() {
        XCTAssertTrue(SliceFileMatch.shouldClean(
            filename: ".550e8400-e29b-41d4-a716-446655440000.tmp", keeping: []))
    }

    func testPreservesRotationJson() {
        XCTAssertFalse(SliceFileMatch.shouldClean(filename: "rotation.json", keeping: []))
    }

    func testPreservesKeepSet() {
        XCTAssertFalse(SliceFileMatch.shouldClean(filename: "a1b2c3d4_12345.jpg",
                                                   keeping: ["a1b2c3d4_12345.jpg"]))
    }

    func testIgnoresNonMatchingFilenames() {
        XCTAssertFalse(SliceFileMatch.shouldClean(filename: "photo.png", keeping: []))
        XCTAssertFalse(SliceFileMatch.shouldClean(filename: "notes.txt", keeping: []))
        XCTAssertFalse(SliceFileMatch.shouldClean(filename: ".DS_Store", keeping: []))
        XCTAssertFalse(SliceFileMatch.shouldClean(filename: "too_short_1.jpg", keeping: []))
    }

    func testSliceFilePattern() {
        XCTAssertTrue(SliceFileMatch.isSliceFile("a1b2c3d4_99.jpg"))
        XCTAssertTrue(SliceFileMatch.isSliceFile("ABCDEF01_0.jpg"))
        XCTAssertFalse(SliceFileMatch.isSliceFile("a1b2c3d4.jpg"))
        XCTAssertFalse(SliceFileMatch.isSliceFile("a1b2c3d4_99.png"))
        XCTAssertFalse(SliceFileMatch.isSliceFile("toolong123_1.jpg"))
    }

    func testTempFilePattern() {
        XCTAssertTrue(SliceFileMatch.isTempFile(".550e8400-e29b-41d4-a716-446655440000.tmp"))
        XCTAssertFalse(SliceFileMatch.isTempFile("550e8400.tmp"))
        XCTAssertFalse(SliceFileMatch.isTempFile(".foo.jpg"))
    }
}
