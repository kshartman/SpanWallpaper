import Foundation

public enum AppPaths {
    public static let supportDir: URL = {
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

    public static let configURL: URL = supportDir.appendingPathComponent("config.json")
    public static let errorURL: URL = supportDir.appendingPathComponent("last-error.txt")
}
