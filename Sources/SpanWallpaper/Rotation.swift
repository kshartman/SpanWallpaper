import Foundation
import SpanWallpaperLib

// MARK: - Folder Image Cache

final class FolderImageCache {
    static let shared = FolderImageCache()
    private var cachedPath: String?
    private var cachedOptions: ScanOptions?
    private var cachedFiles: [URL] = []

    func imageFiles(in folderURL: URL, options: ScanOptions) -> [URL] {
        let path = folderURL.path
        if path == cachedPath && options == cachedOptions { return cachedFiles }
        cachedFiles = scanImages(in: folderURL, options: options)
        cachedPath = path
        cachedOptions = options
        return cachedFiles
    }

    func invalidate() {
        cachedPath = nil
        cachedOptions = nil
        cachedFiles = []
    }
}

func imageFiles(in folderURL: URL, options: ScanOptions = ScanOptions()) -> [URL] {
    FolderImageCache.shared.imageFiles(in: folderURL, options: options)
}

// MARK: - Rotation Manager

class RotationManager {
    static let shared = RotationManager()

    private var timer: Timer?
    var config: AppConfig?
    var lastAppliedImagePath: String?

    private var shuffledQueue: [URL] = []
    private var shuffleIndex = 0

    var isActive: Bool { config?.folderPath != nil }

    var folderName: String? {
        guard let path = config?.folderPath else { return nil }
        return (path as NSString).lastPathComponent
    }

    func scanOptions() -> ScanOptions {
        guard let config = config else { return ScanOptions() }
        return ScanOptions(from: config)
    }

    func start(folderPath: String, intervalSeconds: Int? = nil,
              displayMode: DisplayMode? = nil, playMode: PlayMode? = nil) {
        timer?.invalidate()
        timer = nil
        uninstallLaunchAgent()

        if config == nil { config = AppConfig.load() ?? AppConfig() }
        config?.folderPath = folderPath
        config?.singleImagePath = nil
        if let interval = intervalSeconds {
            config?.intervalSeconds = interval
        }
        if let mode = displayMode {
            config?.displayMode = mode
        }
        if let play = playMode {
            config?.playMode = play
        }
        config?.save()

        resetShuffle()
        applyNext()
        WallpaperSetter.writeSkipMarker()
        installLaunchAgent()
        scheduleTimer()
        Log.info("Rotation started: \(folderPath), interval \(config?.intervalSeconds ?? AppConfig.defaultInterval)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        shuffledQueue = []
        shuffleIndex = 0

        if config?.folderPath != nil {
            uninstallLaunchAgent()
        }
        config?.folderPath = nil
        config?.lastImagePath = nil
        lastAppliedImagePath = nil
        config?.save()
        Log.info("Rotation stopped.")
    }

    func applyNext() {
        guard let config = config, let folderPath = config.folderPath else { return }
        let folder = URL(fileURLWithPath: folderPath)

        guard FileManager.default.isReadableFile(atPath: folder.path) else {
            Log.info("Folder unavailable: \(folderPath) -- skipping tick")
            return
        }

        FolderImageCache.shared.invalidate()
        let options = scanOptions()
        let images = imageFiles(in: folder, options: options)
        guard !images.isEmpty else {
            Log.info("No images in \(folderPath)")
            return
        }

        let next: URL?
        switch config.playMode {
        case .sequential:
            next = pickNextImage(from: images, lastUsed: config.lastImagePath, playMode: .sequential)
        case .shuffle:
            next = nextShuffled(from: images)
        }

        guard let nextImage = next else {
            Log.info("No images in \(folderPath)")
            return
        }

        do {
            try WallpaperSetter.withProcessLock {
                try processImage(at: nextImage.path, displayMode: config.displayMode)
                lastAppliedImagePath = nextImage.path
                self.config?.lastImagePath = nextImage.path
                self.config?.save()
                DebugLog.record(action: "next (\(config.playMode.rawValue))", image: nextImage.path)
            }
        } catch {
            Log.info("Rotation error: \(error)")
        }
    }

    func applyPrevious() {
        guard let config = config, config.playMode == .sequential,
              let folderPath = config.folderPath else { return }
        let folder = URL(fileURLWithPath: folderPath)
        guard FileManager.default.isReadableFile(atPath: folder.path) else { return }

        FolderImageCache.shared.invalidate()
        let options = scanOptions()
        let images = imageFiles(in: folder, options: options)
        guard let prev = pickPreviousImage(from: images, lastUsed: config.lastImagePath) else { return }

        do {
            try WallpaperSetter.withProcessLock {
                try processImage(at: prev.path, displayMode: config.displayMode)
                lastAppliedImagePath = prev.path
                self.config?.lastImagePath = prev.path
                self.config?.save()
                DebugLog.record(action: "previous", image: prev.path)
            }
        } catch {
            Log.info("Previous error: \(error)")
        }
    }

    func reapplyCurrent() {
        if let path = lastAppliedImagePath ?? config?.lastImagePath {
            guard FileManager.default.fileExists(atPath: path) else {
                Log.info("Last image no longer exists: \(path)")
                return
            }
            do {
                try WallpaperSetter.withProcessLock {
                    try processImage(at: path, displayMode: config?.displayMode ?? .span)
                }
                Log.info("Re-applied current wallpaper.")
                DebugLog.record(action: "reapply", image: path)
            } catch {
                Log.info("Re-apply error: \(error)")
            }
        }
    }

    func retireCurrent() {
        guard isActive, let config = config, let folderPath = config.folderPath else { return }
        guard let currentPath = lastAppliedImagePath ?? config.lastImagePath else { return }
        let imageURL = URL(fileURLWithPath: currentPath)

        let folder = URL(fileURLWithPath: folderPath)
        FolderImageCache.shared.invalidate()
        let images = imageFiles(in: folder, options: scanOptions())
        let successor = pickNextImage(from: images, lastUsed: currentPath, playMode: config.playMode)

        let retiredDir = imageURL.deletingLastPathComponent()
            .appendingPathComponent("retired", isDirectory: true)

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: retiredDir, withIntermediateDirectories: true)
            var dest = retiredDir.appendingPathComponent(imageURL.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                let stem = imageURL.deletingPathExtension().lastPathComponent
                let ext = imageURL.pathExtension
                var counter = 1
                repeat {
                    let name = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
                    dest = retiredDir.appendingPathComponent(name)
                    counter += 1
                } while fm.fileExists(atPath: dest.path)
            }
            try fm.moveItem(at: imageURL, to: dest)
            Log.info("Retired: \(imageURL.lastPathComponent) -> retired/\(dest.lastPathComponent)")
            DebugLog.record(action: "retire", image: imageURL.path)
        } catch {
            Log.info("Retire failed: \(error)")
            return
        }

        FolderImageCache.shared.invalidate()
        resetShuffle()

        guard let nextImage = successor else { return }
        do {
            try WallpaperSetter.withProcessLock {
                try processImage(at: nextImage.path, displayMode: config.displayMode)
                lastAppliedImagePath = nextImage.path
                self.config?.lastImagePath = nextImage.path
                self.config?.save()
                DebugLog.record(action: "next (\(config.playMode.rawValue))", image: nextImage.path)
            }
        } catch {
            Log.info("Rotation error after retire: \(error)")
        }
    }

    func resume() {
        guard let saved = AppConfig.load() else { return }
        config = saved

        if let folderPath = saved.folderPath {
            let folder = URL(fileURLWithPath: folderPath)
            guard FileManager.default.fileExists(atPath: folder.path) else {
                config?.folderPath = nil
                config?.save()
                return
            }
            lastAppliedImagePath = saved.lastImagePath
            scheduleTimer()
            Log.info("Resumed rotation: \(folderPath)")
            if let last = saved.lastImagePath {
                DebugLog.record(action: "resume-rotation", image: last)
            }
        } else if let singlePath = saved.singleImagePath {
            guard FileManager.default.fileExists(atPath: singlePath) else { return }
            do {
                try processImage(at: singlePath, displayMode: saved.displayMode)
                lastAppliedImagePath = singlePath
                Log.info("Reapplied single image: \(singlePath)")
                DebugLog.record(action: "resume-single", image: singlePath)
            } catch {
                Log.info("Reapply error: \(error)")
            }
        }
    }


    // MARK: - Monitor-count folder switching

    func switchFolderIfNeeded(displayCount: Int) {
        guard let config = config,
              let folders = config.monitorFolders,
              let folder = folders[String(displayCount)],
              !folder.isEmpty,
              folder != config.folderPath,
              FileManager.default.fileExists(atPath: folder) else { return }

        Log.info("Display count changed to \(displayCount), switching to: \(folder)")
        DebugLog.record(action: "display-switch (count=\(displayCount))", image: folder)
        self.config?.folderPath = folder
        self.config?.lastImagePath = nil
        self.config?.save()
        FolderImageCache.shared.invalidate()
        resetShuffle()
        applyNext()

        if isActive {
            WallpaperSetter.writeSkipMarker()
            uninstallLaunchAgent()
            installLaunchAgent()
        }
    }

    // MARK: - Shuffle

    func resetShuffle() {
        shuffledQueue = []
        shuffleIndex = 0
    }

    private func nextShuffled(from images: [URL]) -> URL? {
        guard !images.isEmpty else { return nil }
        if shuffledQueue.isEmpty || shuffleIndex >= shuffledQueue.count {
            shuffledQueue = images.shuffled()
            shuffleIndex = 0
        }
        let result = shuffledQueue[shuffleIndex]
        shuffleIndex += 1
        return result
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        guard let config = config else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.intervalSeconds), repeats: true) { [weak self] _ in
            self?.applyNext()
        }
    }

    // MARK: - LaunchAgent

    private var launchAgentURL: URL {
        let lib = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        return lib.appendingPathComponent("com.shartman.SpanWallpaper.plist")
    }

    private var appBinaryPath: String {
        Bundle.main.executablePath ?? "/Applications/SpanWallpaper.app/Contents/MacOS/SpanWallpaper"
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func installLaunchAgent() {
        guard let config = config else { return }
        let binaryXML = RotationManager.xmlEscape(appBinaryPath)
        var envBlock = ""
        if let customDir = ProcessInfo.processInfo.environment["SPAN_WALLPAPER_DIR"] {
            let escaped = RotationManager.xmlEscape(customDir)
            envBlock = """

                <key>EnvironmentVariables</key>
                <dict>
                    <key>SPAN_WALLPAPER_DIR</key>
                    <string>\(escaped)</string>
                </dict>
            """
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.shartman.SpanWallpaper</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryXML)</string>
                <string>--rotate</string>
            </array>
            <key>StartInterval</key>
            <integer>\(config.intervalSeconds)</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/tmp/SpanWallpaper.log</string>\(envBlock)
        </dict>
        </plist>
        """
        let label = "com.shartman.SpanWallpaper"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "gui/\(getuid())", launchAgentURL.path]
        try? proc.run()
        proc.waitUntilExit()

        try? plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)

        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        load.arguments = ["bootstrap", "gui/\(getuid())", launchAgentURL.path]
        try? load.run()
        load.waitUntilExit()
        Log.info("LaunchAgent installed: \(label)")
    }

    private func uninstallLaunchAgent() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "gui/\(getuid())", launchAgentURL.path]
        try? proc.run()
        proc.waitUntilExit()
        try? FileManager.default.removeItem(at: launchAgentURL)
        Log.info("LaunchAgent removed.")
    }
}
