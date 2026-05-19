import AppKit
import Foundation
import SpanWallpaperLib

enum Log {
    static func info(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[span-wallpaper] \(message())\n".utf8))
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("[span-wallpaper] ERROR: \(message)\n".utf8))
        exit(code)
    }
}

enum WallpaperError: Error, CustomStringConvertible {
    case noScreens
    case imageLoadFailed(URL)
    case sliceRenderFailed(screenIndex: Int)
    case writeFailed(URL, underlying: Error)
    case setWallpaperFailed(screenIndex: Int, underlying: Error)
    case noImagesInFolder(URL)

    var description: String {
        switch self {
        case .noScreens:
            return "No screens detected."
        case .imageLoadFailed(let url):
            return "Could not decode image at \(url.path)."
        case .sliceRenderFailed(let i):
            return "Failed to render slice for screen index \(i)."
        case .writeFailed(let url, let err):
            return "Failed to write \(url.path): \(err.localizedDescription)"
        case .setWallpaperFailed(let i, let err):
            return "Failed to set wallpaper on screen index \(i): \(err.localizedDescription)"
        case .noImagesInFolder(let url):
            return "No image files found in \(url.path)."
        }
    }
}

enum DebugLog {
    private static let logURL = AppPaths.supportDir.appendingPathComponent("debug.log")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func record(action: String, images: [String]) {
        guard AppConfig.load()?.debugLog == true else { return }
        let ts = dateFormatter.string(from: Date())
        var line = "[\(ts)] \(action)"
        for path in images {
            line += "\n  \(path)"
        }
        line += "\n"
        let data = Data(line.utf8)
        if let fh = try? FileHandle(forWritingTo: logURL) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            try? data.write(to: logURL)
        }
    }

    static func record(action: String, image: String) {
        record(action: action, images: [image])
    }
}

func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "SpanWallpaper"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.runModal()
}
