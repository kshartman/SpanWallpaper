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

    static let configURL: URL = supportDir.appendingPathComponent("rotation.json")

    private(set) static var lastSliceFiles: [CGDirectDisplayID: URL] = [:]

    static func apply(sliceFiles: [(slice: ScreenSlice, url: URL)]) {
        var mapping: [CGDirectDisplayID: URL] = [:]
        for (slice, url) in sliceFiles { mapping[slice.displayID] = url }
        lastSliceFiles = mapping
        applyToCurrentScreens()
        cleanupOldFiles(keeping: Set(mapping.values.map { $0.lastPathComponent }))
    }

    static func reapplyLastSlices() {
        guard !lastSliceFiles.isEmpty else { return }
        Log.info("Apply-only reapply (\(lastSliceFiles.count) cached slices)")
        applyToCurrentScreens()
    }

    private static func applyToCurrentScreens() {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue),
            .allowClipping: NSNumber(value: true)
        ]

        let applyBlock = {
            for screen in NSScreen.screens {
                let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
                guard let url = lastSliceFiles[did] else {
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

    private static func cleanupOldFiles(keeping keep: Set<String>) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) else { return }
        for url in items {
            if SliceFileMatch.shouldClean(filename: url.lastPathComponent, keeping: keep) {
                try? fm.removeItem(at: url)
            }
        }
    }
}
