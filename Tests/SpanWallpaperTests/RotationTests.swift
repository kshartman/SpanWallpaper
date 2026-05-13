import XCTest
@testable import SpanWallpaperLib

final class PickNextTests: XCTestCase {

    private func urls(_ names: String...) -> [URL] {
        names.map { URL(fileURLWithPath: "/images/\($0)") }
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(pickNextImage(from: [], lastUsed: nil))
    }

    func testSingleReturnsIt() {
        let list = urls("a.jpg")
        let result = pickNextImage(from: list, lastUsed: nil)
        XCTAssertEqual(result, list[0])
    }

    func testNoLastUsedReturnsElement() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: nil)
        XCTAssertNotNil(result)
        XCTAssertTrue(list.contains(result!))
    }

    func testLastUsedReturnsNext() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/a.jpg")
        XCTAssertEqual(result, list[1])
    }

    func testWrapsToFirst() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/c.jpg")
        XCTAssertEqual(result, list[0])
    }

    func testDeletedLastUsedReturnsRandom() {
        let list = urls("a.jpg", "b.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/gone.jpg")
        XCTAssertNotNil(result)
        XCTAssertTrue(list.contains(result!))
    }

    func testDuplicatePathsInList() {
        let list = urls("a.jpg", "a.jpg", "b.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/a.jpg")
        XCTAssertEqual(result, list[1])
    }
}

final class RotationConfigTests: XCTestCase {

    func testRoundTrip() throws {
        let config = RotationConfig(folderPath: "/Users/test/wallpapers",
                                    intervalSeconds: 3600,
                                    lastImagePath: "/Users/test/wallpapers/sunset.jpg")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RotationConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testMissingLastImagePathDecodesAsNil() throws {
        let json = """
        {"folderPath":"/tmp","intervalSeconds":86400}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(RotationConfig.self, from: json)
        XCTAssertNil(config.lastImagePath)
        XCTAssertEqual(config.folderPath, "/tmp")
        XCTAssertEqual(config.intervalSeconds, 86400)
    }

    func testEmptyFolderPath() throws {
        let config = RotationConfig(folderPath: "", intervalSeconds: 3600)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RotationConfig.self, from: data)
        XCTAssertEqual(decoded.folderPath, "")
    }
}

final class IntervalPresetTests: XCTestCase {

    func testExactMatch() {
        XCTAssertEqual(IntervalPreset.indexForSeconds(3600), 1)
        XCTAssertEqual(IntervalPreset.indexForSeconds(86400), 4)
        XCTAssertEqual(IntervalPreset.indexForSeconds(604800), 6)
    }

    func testNonMatchingDefaultsToDaily() {
        XCTAssertEqual(IntervalPreset.indexForSeconds(9999), 4)
        XCTAssertEqual(IntervalPreset.indexForSeconds(0), 4)
        XCTAssertEqual(IntervalPreset.indexForSeconds(-1), 4)
    }
}
