import AppKit
import SpanWallpaperLib

enum WallpaperSetter {
    static let supportDir: URL = {
        let fm = FileManager.default
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["SPAN_WALLPAPER_DIR"] {
            dir = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = base.appendingPathComponent("SpanWallpaper", isDirectory: true)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let configURL: URL = supportDir.appendingPathComponent("config.json")
    static let errorURL: URL = supportDir.appendingPathComponent("last-error.txt")

    private static let queue = DispatchQueue(label: "com.shartman.SpanWallpaper.sliceFiles")
    private static var _lastSliceFiles: [CGDirectDisplayID: URL] = [:]

    static var lastSliceFiles: [CGDirectDisplayID: URL] {
        queue.sync { _lastSliceFiles }
    }

    // MARK: - Span mode apply

    static func apply(sliceFiles: [(slice: ScreenSlice, url: URL)]) {
        var mapping: [CGDirectDisplayID: URL] = [:]
        for (slice, url) in sliceFiles { mapping[slice.displayID] = url }

        let snapshot = mapping
        let keepSet = Set(mapping.values.map { $0.lastPathComponent })

        queue.sync { _lastSliceFiles = mapping }
        applyToCurrentScreens(snapshot: snapshot)
        cleanupOldFiles(keeping: keepSet)
    }

    static func reapplyLastSlices() {
        let snapshot = lastSliceFiles
        guard !snapshot.isEmpty else { return }
        Log.info("Apply-only reapply (\(snapshot.count) cached slices)")
        applyToCurrentScreens(snapshot: snapshot)
    }

    private static func applyToCurrentScreens(snapshot: [CGDirectDisplayID: URL]) {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue),
            .allowClipping: NSNumber(value: true)
        ]

        let applyBlock = {
            for screen in NSScreen.screens {
                let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
                guard let url = snapshot[did] else {
                    Log.info("  apply: no cached slice for displayID=\(did), skipping")
                    continue
                }
                Log.info("  apply displayID=\(did) frame=\(screen.frame) scale=\(screen.backingScaleFactor) -> \(url.lastPathComponent)")
                do {
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
                } catch {
                    Log.info("  FAILED displayID=\(did): \(error.localizedDescription)")
                }
            }
        }

        if Thread.isMainThread {
            applyBlock()
        } else {
            DispatchQueue.main.async { applyBlock() }
        }
    }

    // MARK: - Fit/Fill mode apply

    static func applyOriginalToAllScreens(imageURL: URL, mode: DisplayMode) {
        let scaling: NSImageScaling
        let clip: Bool
        switch mode {
        case .fit:
            scaling = .scaleProportionallyUpOrDown
            clip = false
        case .fill:
            scaling = .scaleProportionallyUpOrDown
            clip = true
        case .span:
            return
        }

        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: scaling.rawValue),
            .allowClipping: NSNumber(value: clip)
        ]

        let applyBlock = {
            for screen in NSScreen.screens {
                let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
                Log.info("  apply \(mode.rawValue) displayID=\(did) -> \(imageURL.lastPathComponent)")
                do {
                    try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: options)
                } catch {
                    Log.info("  FAILED displayID=\(did): \(error.localizedDescription)")
                }
            }
        }

        if Thread.isMainThread {
            applyBlock()
        } else {
            DispatchQueue.main.async { applyBlock() }
        }
    }

    // MARK: - Slice cache management

    static func clearSliceCache() {
        queue.sync { _lastSliceFiles = [:] }
        cleanupOldFiles(keeping: [])
    }

    static func cleanupOldFiles(keeping keep: Set<String>) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) else { return }
        for url in items {
            if SliceFileMatch.shouldClean(filename: url.lastPathComponent, keeping: keep) {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Error file

    static func writeError(_ message: String) {
        try? message.data(using: .utf8)?.write(to: errorURL)
    }

    static func clearError() {
        try? FileManager.default.removeItem(at: errorURL)
    }

    static func readError() -> String? {
        try? String(contentsOf: errorURL, encoding: .utf8)
    }

    // MARK: - Skip marker (prevents RunAtLoad tick after fresh install)

    private static let skipMarkerURL: URL = supportDir.appendingPathComponent(".skip-next-tick")

    static func writeSkipMarker() {
        try? Data().write(to: skipMarkerURL)
    }

    static func consumeSkipMarker() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skipMarkerURL.path) else { return false }
        try? fm.removeItem(at: skipMarkerURL)
        return true
    }

    // MARK: - Cross-process lock

    private static let lockURL: URL = supportDir.appendingPathComponent(".lock")

    static func withProcessLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
