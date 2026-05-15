import XCTest
@testable import SpanWallpaperLib

final class ScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createFile(_ relativePath: String) {
        let url = tempDir.appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    // MARK: - Flat vs recursive

    func testFlatScan() {
        createFile("a.jpg")
        createFile("b.png")
        createFile("c.txt")

        let results = scanImages(in: tempDir, options: ScanOptions(recursive: false, excludePatterns: []))
        XCTAssertEqual(results.map { $0.lastPathComponent }, ["a.jpg", "b.png"])
    }

    func testRecursiveScan() {
        createFile("a.jpg")
        createFile("sub/b.png")
        createFile("sub/deep/c.heic")

        let results = scanImages(in: tempDir, options: ScanOptions(recursive: true, excludePatterns: []))
        XCTAssertEqual(results.count, 3)
    }

    func testNonRecursiveSkipsSubdirs() {
        createFile("a.jpg")
        createFile("sub/b.png")

        let results = scanImages(in: tempDir, options: ScanOptions(recursive: false, excludePatterns: []))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].lastPathComponent, "a.jpg")
    }

    // MARK: - Exclude patterns

    func testExcludeRetiredFolder() {
        createFile("a.jpg")
        createFile("retired/b.jpg")
        createFile("sub/c.jpg")

        let results = scanImages(in: tempDir, options: ScanOptions(
            recursive: true, excludePatterns: ["retired"]))
        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results.contains(where: { $0.path.contains("/retired/") }))
    }

    func testMultipleExcludePatterns() {
        createFile("a.jpg")
        createFile("retired/b.jpg")
        createFile("archive/c.jpg")
        createFile("sub/d.jpg")

        let results = scanImages(in: tempDir, options: ScanOptions(
            recursive: true, excludePatterns: ["retired", "archive"]))
        XCTAssertEqual(results.count, 2)
    }

    func testGlobExcludePattern() {
        createFile("a.jpg")
        createFile("old-photos/b.jpg")
        createFile("old-wallpapers/c.jpg")
        createFile("new/d.jpg")

        let results = scanImages(in: tempDir, options: ScanOptions(
            recursive: true, excludePatterns: ["old-*"]))
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Edge cases

    func testEmptyFolder() {
        let results = scanImages(in: tempDir, options: ScanOptions())
        XCTAssertTrue(results.isEmpty)
    }

    func testSortedOutput() {
        createFile("c.jpg")
        createFile("a.jpg")
        createFile("b.jpg")

        let results = scanImages(in: tempDir, options: ScanOptions(recursive: false, excludePatterns: []))
        XCTAssertEqual(results.map { $0.lastPathComponent }, ["a.jpg", "b.jpg", "c.jpg"])
    }

    func testAllImageExtensions() {
        for ext in imageExtensions {
            createFile("test.\(ext)")
        }
        createFile("test.txt")
        createFile("test.pdf")

        let results = scanImages(in: tempDir, options: ScanOptions(recursive: false, excludePatterns: []))
        XCTAssertEqual(results.count, imageExtensions.count)
    }

    // MARK: - Exclude pattern matching

    func testMatchesExcludePatternExact() {
        XCTAssertTrue(matchesExcludePattern("retired", patterns: ["retired"]))
        XCTAssertFalse(matchesExcludePattern("photos", patterns: ["retired"]))
    }

    func testMatchesExcludePatternGlob() {
        XCTAssertTrue(matchesExcludePattern("old-photos", patterns: ["old-*"]))
        XCTAssertTrue(matchesExcludePattern("old-wallpapers", patterns: ["old-*"]))
        XCTAssertFalse(matchesExcludePattern("new-photos", patterns: ["old-*"]))
    }

    func testMatchesExcludePatternEmpty() {
        XCTAssertFalse(matchesExcludePattern("anything", patterns: []))
    }

    // MARK: - ScanOptions from AppConfig

    func testScanOptionsFromAppConfig() {
        let config = AppConfig(
            recursive: false,
            excludePatterns: ["retired", "archive"],
            minWidth: 1920,
            maxHeight: 4000
        )
        let opts = ScanOptions(from: config)
        XCTAssertFalse(opts.recursive)
        XCTAssertEqual(opts.excludePatterns, ["retired", "archive"])
        XCTAssertEqual(opts.minWidth, 1920)
        XCTAssertNil(opts.minHeight)
        XCTAssertNil(opts.maxWidth)
        XCTAssertEqual(opts.maxHeight, 4000)
        XCTAssertTrue(opts.hasSizeFilter)
    }

    func testScanOptionsNoSizeFilter() {
        let opts = ScanOptions()
        XCTAssertFalse(opts.hasSizeFilter)
    }
}
