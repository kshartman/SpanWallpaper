import XCTest
@testable import SpanWallpaperLib

// MARK: - AppConfig Tests

final class AppConfigTests: XCTestCase {

    func testRoundTrip() throws {
        let config = AppConfig(
            folderPath: "/path",
            intervalSeconds: 3600,
            playMode: .shuffle,
            lastImagePath: "/path/img.jpg",
            recursive: true,
            excludePatterns: ["retired", "archive"],
            minWidth: 1920,
            displayMode: .span
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testDefaultValues() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertNil(config.folderPath)
        XCTAssertNil(config.singleImagePath)
        XCTAssertEqual(config.intervalSeconds, 86400)
        XCTAssertEqual(config.playMode, .shuffle)
        XCTAssertNil(config.lastImagePath)
        XCTAssertTrue(config.recursive)
        XCTAssertEqual(config.excludePatterns, ["retired"])
        XCTAssertNil(config.minWidth)
        XCTAssertNil(config.minHeight)
        XCTAssertNil(config.maxWidth)
        XCTAssertNil(config.maxHeight)
        XCTAssertEqual(config.displayMode, .span)
    }

    func testDecodesFromOldRotationJson() throws {
        let json = """
        {"folderPath":"/tmp","intervalSeconds":86400,"lastImagePath":"/tmp/a.jpg"}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.folderPath, "/tmp")
        XCTAssertEqual(config.intervalSeconds, 86400)
        XCTAssertEqual(config.lastImagePath, "/tmp/a.jpg")
        XCTAssertEqual(config.playMode, .shuffle)
        XCTAssertTrue(config.recursive)
        XCTAssertEqual(config.displayMode, .span)
    }

    func testAllDisplayModes() throws {
        for mode in DisplayMode.allCases {
            let config = AppConfig(displayMode: mode)
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            XCTAssertEqual(decoded.displayMode, mode)
        }
    }

    func testAllPlayModes() throws {
        for mode in PlayMode.allCases {
            let config = AppConfig(playMode: mode)
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            XCTAssertEqual(decoded.playMode, mode)
        }
    }

    func testSizeFilterFields() throws {
        let config = AppConfig(minWidth: 800, minHeight: 600, maxWidth: 7680, maxHeight: 4320)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.minWidth, 800)
        XCTAssertEqual(decoded.minHeight, 600)
        XCTAssertEqual(decoded.maxWidth, 7680)
        XCTAssertEqual(decoded.maxHeight, 4320)
    }

    func testMonitorFoldersRoundTrip() throws {
        let folders = ["1": "/path/single", "2": "/path/dual"]
        let config = AppConfig(monitorFolders: folders)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.monitorFolders, folders)
    }

    func testMonitorFoldersDefaultNil() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertNil(config.monitorFolders)
    }
}

// MARK: - Legacy RotationConfig (migration source)

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

    func testToAppConfig() {
        let old = RotationConfig(folderPath: "/path", intervalSeconds: 3600, lastImagePath: "/path/a.jpg")
        let migrated = old.toAppConfig()
        XCTAssertEqual(migrated.folderPath, "/path")
        XCTAssertEqual(migrated.intervalSeconds, 3600)
        XCTAssertEqual(migrated.lastImagePath, "/path/a.jpg")
        XCTAssertEqual(migrated.playMode, .shuffle)
        XCTAssertTrue(migrated.recursive)
        XCTAssertEqual(migrated.excludePatterns, ["retired"])
        XCTAssertEqual(migrated.displayMode, .span)
    }
}

// MARK: - Interval Presets

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

// MARK: - Image Selection

final class PickNextTests: XCTestCase {

    private func urls(_ names: String...) -> [URL] {
        names.map { URL(fileURLWithPath: "/images/\($0)") }
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(pickNextImage(from: [], lastUsed: nil))
        XCTAssertNil(pickNextImage(from: [], lastUsed: nil, playMode: .shuffle))
    }

    func testSingleReturnsIt() {
        let list = urls("a.jpg")
        let result = pickNextImage(from: list, lastUsed: nil)
        XCTAssertEqual(result, list[0])
    }

    func testNoLastUsedReturnsFirst() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: nil)
        XCTAssertEqual(result, list[0])
    }

    func testSequentialAdvances() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/a.jpg", playMode: .sequential)
        XCTAssertEqual(result, list[1])
    }

    func testSequentialWraps() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/c.jpg", playMode: .sequential)
        XCTAssertEqual(result, list[0])
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

    func testDeletedLastUsedReturnsFirst() {
        let list = urls("a.jpg", "b.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/gone.jpg")
        XCTAssertEqual(result, list[0])
    }

    func testDuplicatePathsInList() {
        let list = urls("a.jpg", "a.jpg", "b.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/a.jpg")
        XCTAssertEqual(result, list[1])
    }

    func testShuffleReturnsElement() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: nil, playMode: .shuffle)
        XCTAssertNotNil(result)
        XCTAssertTrue(list.contains(result!))
    }

    func testShuffleWithLastUsedReturnsElement() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        let result = pickNextImage(from: list, lastUsed: "/images/a.jpg", playMode: .shuffle)
        XCTAssertNotNil(result)
        XCTAssertTrue(list.contains(result!))
    }
}

// MARK: - Previous Image Selection

final class PickPreviousTests: XCTestCase {

    private func urls(_ names: String...) -> [URL] {
        names.map { URL(fileURLWithPath: "/images/\($0)") }
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(pickPreviousImage(from: [], lastUsed: nil))
    }

    func testSingleReturnsIt() {
        let list = urls("a.jpg")
        XCTAssertEqual(pickPreviousImage(from: list, lastUsed: nil), list[0])
    }

    func testNoLastUsedReturnsLast() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        XCTAssertEqual(pickPreviousImage(from: list, lastUsed: nil), list[2])
    }

    func testStepsBackward() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        XCTAssertEqual(pickPreviousImage(from: list, lastUsed: "/images/c.jpg"), list[1])
    }

    func testWrapsToEnd() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        XCTAssertEqual(pickPreviousImage(from: list, lastUsed: "/images/a.jpg"), list[2])
    }

    func testDeletedLastUsedReturnsLast() {
        let list = urls("a.jpg", "b.jpg")
        XCTAssertEqual(pickPreviousImage(from: list, lastUsed: "/images/gone.jpg"), list[1])
    }

    func testMiddleStepsBack() {
        let list = urls("a.jpg", "b.jpg", "c.jpg")
        XCTAssertEqual(pickPreviousImage(from: list, lastUsed: "/images/b.jpg"), list[0])
    }
}
