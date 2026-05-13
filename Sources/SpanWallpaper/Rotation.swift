import Foundation
import SpanWallpaperLib

func scanImageFiles(in folderURL: URL) -> [URL] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
        at: folderURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
    ) else { return [] }

    var images: [URL] = []
    for case let url as URL in enumerator {
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            images.append(url)
        }
    }
    return images.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

final class FolderImageCache {
    static let shared = FolderImageCache()
    private var cachedPath: String?
    private var cachedFiles: [URL] = []

    func imageFiles(in folderURL: URL) -> [URL] {
        let path = folderURL.path
        if path == cachedPath { return cachedFiles }
        cachedFiles = scanImageFiles(in: folderURL)
        cachedPath = path
        return cachedFiles
    }

    func invalidate() {
        cachedPath = nil
        cachedFiles = []
    }
}

func imageFiles(in folderURL: URL) -> [URL] {
    FolderImageCache.shared.imageFiles(in: folderURL)
}

extension RotationConfig {
    static func load() -> RotationConfig? {
        guard let data = try? Data(contentsOf: WallpaperSetter.configURL) else { return nil }
        return try? JSONDecoder().decode(RotationConfig.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: WallpaperSetter.configURL)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: WallpaperSetter.configURL)
    }
}

class RotationManager {
    static let shared = RotationManager()

    private var timer: Timer?
    private(set) var config: RotationConfig?
    var lastAppliedImagePath: String?

    var isActive: Bool { config != nil }

    var folderName: String? {
        guard let path = config?.folderPath else { return nil }
        return (path as NSString).lastPathComponent
    }

    func start(folderPath: String, intervalSeconds: Int = RotationConfig.defaultInterval) {
        config = RotationConfig(folderPath: folderPath, intervalSeconds: intervalSeconds)
        config?.save()
        installLaunchAgent()
        applyNext()
        scheduleTimer()
        Log.info("Rotation started: \(folderPath), interval \(intervalSeconds)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        config = nil
        lastAppliedImagePath = nil
        RotationConfig.remove()
        uninstallLaunchAgent()
        Log.info("Rotation stopped.")
    }

    func applyNext() {
        guard let config = config else { return }
        let folder = URL(fileURLWithPath: config.folderPath)

        guard FileManager.default.isReadableFile(atPath: folder.path) else {
            Log.info("Folder unavailable (ejected/missing?): \(config.folderPath) -- skipping tick")
            return
        }

        FolderImageCache.shared.invalidate()
        let images = imageFiles(in: folder)
        guard !images.isEmpty else {
            Log.info("No images in \(config.folderPath)")
            return
        }

        guard let next = pickNextImage(from: images, lastUsed: config.lastImagePath) else {
            Log.info("No images in \(config.folderPath)")
            return
        }
        do {
            try processImage(at: next.path)
            lastAppliedImagePath = next.path
            self.config?.lastImagePath = next.path
            self.config?.save()
        } catch {
            Log.info("Rotation error: \(error)")
        }
    }

    func reapplyCurrent() {
        if let path = lastAppliedImagePath ?? config?.lastImagePath {
            guard FileManager.default.fileExists(atPath: path) else {
                Log.info("Last image no longer exists: \(path)")
                return
            }
            do {
                try processImage(at: path)
                Log.info("Re-applied current wallpaper after display/wake change.")
            } catch {
                Log.info("Re-apply error: \(error)")
            }
        }
    }

    func resume() {
        guard let saved = RotationConfig.load() else { return }
        let folder = URL(fileURLWithPath: saved.folderPath)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            RotationConfig.remove()
            return
        }
        config = saved
        scheduleTimer()
        Log.info("Resumed rotation: \(saved.folderPath)")
    }

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
