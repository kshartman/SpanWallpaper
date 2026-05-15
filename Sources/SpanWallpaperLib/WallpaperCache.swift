import Foundation

public enum WallpaperCache {
    public static let directory: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(
            "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.image"
        )
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return path
    }()

    public static func hasAccess() -> Bool {
        guard let dir = directory else { return false }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            return true
        } catch {
            return false
        }
    }

    public static func sizeBytes() -> Int64 {
        guard let dir = directory else { return 0 }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    public static func formattedSize() -> String {
        let bytes = sizeBytes()
        if bytes == 0 { return "empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func purge(keeping: Int = 0) -> Int {
        guard let dir = directory else { return 0 }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let sorted = contents.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da > db
        }

        let toDelete = sorted.dropFirst(keeping)
        var deleted = 0
        for url in toDelete {
            do {
                try fm.removeItem(at: url)
                deleted += 1
            } catch {}
        }
        return deleted
    }
}
