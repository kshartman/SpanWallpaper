#!/usr/bin/env swift
//
//  SpanWallpaper.swift
//
//  Native macOS app that sets a single image as the wallpaper, aspect-filled
//  across every attached display treated as one unified pixel canvas, then
//  sliced at the real pixel seams and applied per-screen.
//
//  Drop an image for one-shot, or drop a folder to rotate on a schedule.
//  Right-click the Dock icon for "Next Wallpaper" / "Stop Rotation".
//

import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Logging

enum Log {
    static func info(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[span-wallpaper] \(message())\n".utf8))
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("[span-wallpaper] ERROR: \(message)\n".utf8))
        exit(code)
    }
}

// MARK: - Errors

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

// MARK: - Screen geometry

struct ScreenSlice {
    let screen: NSScreen
    /// Position within the unified canvas, in points.
    let pointOrigin: CGPoint
    /// Size in points.
    let pointSize: CGSize
    /// Native pixel size: pointSize * backingScaleFactor.
    let pixelSize: CGSize
    let scaleFactor: CGFloat
    let index: Int

    var displayID: CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

struct ScreenLayout {
    let slices: [ScreenSlice]
    /// Combined canvas size in points (consistent coordinate space across DPIs).
    let canvasPointSize: CGSize

    static func detect() throws -> ScreenLayout {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw WallpaperError.noScreens }

        // AppKit point frames: primary screen origin is (0,0) bottom-left;
        // secondary screens have signed offsets. This is already DPI-independent.
        let frames = screens.map { $0.frame }

        let minX = frames.map { $0.minX }.min()!
        let maxX = frames.map { $0.maxX }.max()!
        let minY = frames.map { $0.minY }.min()!
        let maxY = frames.map { $0.maxY }.max()!

        let canvas = CGSize(width: maxX - minX, height: maxY - minY)

        struct Raw { let screen: NSScreen; let frame: CGRect }
        let ordered = screens.map { Raw(screen: $0, frame: $0.frame) }
            .sorted {
                $0.frame.minX != $1.frame.minX
                    ? $0.frame.minX < $1.frame.minX
                    : $0.frame.minY < $1.frame.minY
            }

        // Convert AppKit bottom-left origin to top-left canvas coordinates.
        let slices: [ScreenSlice] = ordered.enumerated().map { (i, r) in
            let scale = r.screen.backingScaleFactor
            return ScreenSlice(
                screen: r.screen,
                pointOrigin: CGPoint(
                    x: r.frame.minX - minX,
                    y: maxY - r.frame.maxY
                ),
                pointSize: r.frame.size,
                pixelSize: CGSize(
                    width: r.frame.width * scale,
                    height: r.frame.height * scale
                ),
                scaleFactor: scale,
                index: i
            )
        }

        return ScreenLayout(slices: slices, canvasPointSize: canvas)
    }
}

// MARK: - Image pipeline

enum ImagePipeline {

    private static let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    static func loadCGImage(from url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw WallpaperError.imageLoadFailed(url)
        }
        guard let raw = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw WallpaperError.imageLoadFailed(url)
        }

        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard orientation != 1 else { return raw }

        let ci = CIImage(cgImage: raw)
            .oriented(forExifOrientation: Int32(orientation))
        guard let baked = ciContext.createCGImage(ci, from: ci.extent) else {
            throw WallpaperError.imageLoadFailed(url)
        }
        return baked
    }

    static func sourceFillRect(sourceSize src: CGSize, canvas: CGSize) -> CGRect {
        let srcAspect = src.width / src.height
        let canvasAspect = canvas.width / canvas.height

        if srcAspect > canvasAspect {
            let cropW = src.height * canvasAspect
            return CGRect(x: (src.width - cropW) / 2.0, y: 0,
                          width: cropW, height: src.height)
        } else {
            let cropH = src.width / canvasAspect
            return CGRect(x: 0, y: (src.height - cropH) / 2.0,
                          width: src.width, height: cropH)
        }
    }

    /// Renders one screen's portion of the aspect-filled canvas.
    /// Layout math uses point-space; output is at the screen's native pixel resolution.
    static func renderSlice(
        source: CGImage,
        sourceFillRect srcFill: CGRect,
        canvasPoints: CGSize,
        slice: ScreenSlice
    ) throws -> CGImage {
        // Map this screen's point-space rect into source-pixel coordinates.
        let sx = srcFill.width / canvasPoints.width
        let sy = srcFill.height / canvasPoints.height
        let srcRect = CGRect(
            x: srcFill.origin.x + slice.pointOrigin.x * sx,
            y: srcFill.origin.y + slice.pointOrigin.y * sy,
            width: slice.pointSize.width * sx,
            height: slice.pointSize.height * sy
        )

        let cropRect = CGRect(
            x: floor(srcRect.origin.x),
            y: floor(srcRect.origin.y),
            width: ceil(srcRect.width),
            height: ceil(srcRect.height)
        )
        guard let cropped = source.cropping(to: cropRect) else {
            throw WallpaperError.sliceRenderFailed(screenIndex: slice.index)
        }

        let outW = Int(slice.pixelSize.width.rounded())
        let outH = Int(slice.pixelSize.height.rounded())
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw WallpaperError.sliceRenderFailed(screenIndex: slice.index)
        }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))

        guard let out = ctx.makeImage() else {
            throw WallpaperError.sliceRenderFailed(screenIndex: slice.index)
        }
        return out
    }

    /// Writes JPEG atomically: renders to a temp file, then renames into place.
    static func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat = 0.92) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)

        guard let dest = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw WallpaperError.writeFailed(url, underlying: NSError(
                domain: "SpanWallpaper", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CGImageDestination init failed"]
            ))
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw WallpaperError.writeFailed(url, underlying: NSError(
                domain: "SpanWallpaper", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "CGImageDestination finalize failed"]
            ))
        }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw WallpaperError.writeFailed(url, underlying: error)
        }
    }
}

// MARK: - Wallpaper setter

enum WallpaperSetter {
    // SPAN_WALLPAPER_DIR overrides; default is ~/Library/Application Support/SpanWallpaper (symlinkable)
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

    private static let sliceFilePattern = try! NSRegularExpression(pattern: "^[0-9A-Fa-f]{8}_\\d+\\.jpg$")
    private static let tempFilePattern = try! NSRegularExpression(pattern: "^\\.[0-9A-Fa-f-]+\\.tmp$")

    /// Last rendered slice mapping: displayID → file URL. Used for apply-only Space reapply.
    private(set) static var lastSliceFiles: [CGDirectDisplayID: URL] = [:]

    /// Apply pre-written slice files as wallpapers, then clean up old files.
    static func apply(sliceFiles: [(slice: ScreenSlice, url: URL)]) {
        var mapping: [CGDirectDisplayID: URL] = [:]
        for (slice, url) in sliceFiles { mapping[slice.displayID] = url }
        lastSliceFiles = mapping
        applyToCurrentScreens()
        cleanupOldFiles(keeping: Set(mapping.values.map { $0.lastPathComponent }))
    }

    /// Apply-only: reuse last rendered slices without re-rendering. For Space changes.
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
        let preserve = keep.union(["rotation.json"])
        guard let items = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) else { return }
        for url in items {
            let name = url.lastPathComponent
            if preserve.contains(name) { continue }
            let range = NSRange(name.startIndex..., in: name)
            let isSlice = sliceFilePattern.firstMatch(in: name, range: range) != nil
            let isTemp = tempFilePattern.firstMatch(in: name, range: range) != nil
            if isSlice || isTemp {
                try? fm.removeItem(at: url)
            }
        }
    }
}

// MARK: - Folder scanning

let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "webp"]

private func scanImageFiles(in folderURL: URL) -> [URL] {
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

// MARK: - Rotation config

struct RotationConfig: Codable {
    var folderPath: String
    var intervalSeconds: Int
    var lastImagePath: String?

    static let defaultInterval = 86400

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

// MARK: - Rotation manager

class RotationManager {
    static let shared = RotationManager()

    private var timer: Timer?
    private(set) var config: RotationConfig?
    /// Path of the last successfully applied image (for re-apply on screen change/wake).
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

        let next = pickNext(from: images, lastUsed: config.lastImagePath)
        do {
            try processImage(at: next.path)
            lastAppliedImagePath = next.path
            self.config?.lastImagePath = next.path
            self.config?.save()
        } catch {
            Log.info("Rotation error: \(error)")
        }
    }

    /// Re-apply the current wallpaper without advancing. Used after screen change or wake.
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

    private func pickNext(from images: [URL], lastUsed: String?) -> URL {
        guard let last = lastUsed,
              let idx = images.firstIndex(where: { $0.path == last }) else {
            return images.randomElement()!
        }
        let nextIdx = (idx + 1) % images.count
        return images[nextIdx]
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
        // Unload first if already loaded
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

// MARK: - Core processing

func processImage(at path: String) throws {
    let inputURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL

    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw WallpaperError.imageLoadFailed(inputURL)
    }

    let layout = try ScreenLayout.detect()
    Log.info("Screens: \(layout.slices.count) -- canvas \(Int(layout.canvasPointSize.width))x\(Int(layout.canvasPointSize.height))pt")
    for s in layout.slices {
        Log.info("  screen[\(s.index)] pt=(\(Int(s.pointOrigin.x)),\(Int(s.pointOrigin.y))) \(Int(s.pointSize.width))x\(Int(s.pointSize.height))pt -> \(Int(s.pixelSize.width))x\(Int(s.pixelSize.height))px @\(s.scaleFactor)x")
    }

    let source = try ImagePipeline.loadCGImage(from: inputURL)
    let sourceSize = CGSize(width: source.width, height: source.height)
    Log.info("Source: \(Int(sourceSize.width))x\(Int(sourceSize.height))px")

    let fillRect = ImagePipeline.sourceFillRect(sourceSize: sourceSize, canvas: layout.canvasPointSize)
    Log.info("Source crop rect: \(Int(fillRect.origin.x)),\(Int(fillRect.origin.y)) \(Int(fillRect.width))x\(Int(fillRect.height))")

    let runID = UUID().uuidString.prefix(8)
    var sliceFiles: [(slice: ScreenSlice, url: URL)] = []
    sliceFiles.reserveCapacity(layout.slices.count)

    for slice in layout.slices {
        let rendered = try ImagePipeline.renderSlice(
            source: source,
            sourceFillRect: fillRect,
            canvasPoints: layout.canvasPointSize,
            slice: slice
        )
        let filename = "\(runID)_\(slice.displayID).jpg"
        let fileURL = WallpaperSetter.supportDir.appendingPathComponent(filename)
        try ImagePipeline.writeJPEG(rendered, to: fileURL)
        sliceFiles.append((slice: slice, url: fileURL))
    }

    WallpaperSetter.apply(sliceFiles: sliceFiles)
    RotationManager.shared.lastAppliedImagePath = path
    Log.info("Applied wallpaper across \(layout.slices.count) display(s).")
}

func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "SpanWallpaper"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.runModal()
}

// MARK: - Interval presets

struct IntervalPreset {
    let title: String
    let seconds: Int
    static let all: [IntervalPreset] = [
        IntervalPreset(title: "Every 30 minutes", seconds: 1800),
        IntervalPreset(title: "Every hour", seconds: 3600),
        IntervalPreset(title: "Every 6 hours", seconds: 21600),
        IntervalPreset(title: "Every 12 hours", seconds: 43200),
        IntervalPreset(title: "Every day", seconds: 86400),
        IntervalPreset(title: "Every 3 days", seconds: 259200),
        IntervalPreset(title: "Every week", seconds: 604800),
    ]

    static func indexForSeconds(_ s: Int) -> Int {
        if let exact = all.firstIndex(where: { $0.seconds == s }) { return exact }
        return all.firstIndex(where: { $0.seconds == 86400 }) ?? 4
    }
}

// MARK: - Drop zone (top area of preferences window)

class DropZoneView: NSView {
    var isDragHighlighted = false
    var onDrop: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isDragHighlighted
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor(white: 0.13, alpha: 1)
        bg.setFill()
        bounds.fill()

        let inset = bounds.insetBy(dx: 16, dy: 12)
        let dash = NSBezierPath(roundedRect: inset, xRadius: 12, yRadius: 12)
        dash.lineWidth = 2
        let pattern: [CGFloat] = [6, 5]
        dash.setLineDash(pattern, count: 2, phase: 0)
        (isDragHighlighted
            ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.9)
            : NSColor(white: 0.30, alpha: 1)
        ).setStroke()
        dash.stroke()

        let text = "Drop image or folder"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: isDragHighlighted
                ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
                : NSColor(white: 0.45, alpha: 1)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func droppedFileURLs(from info: NSDraggingInfo) -> [URL] {
        guard let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return [] }
        return urls
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = droppedFileURLs(from: sender)
        let valid = urls.contains { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue || imageExtensions.contains(url.pathExtension.lowercased())
        }
        isDragHighlighted = valid
        needsDisplay = true
        return valid ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        needsDisplay = true
        let urls = droppedFileURLs(from: sender)
        guard let url = urls.first else { return false }
        onDrop?(url)
        return true
    }
}

// MARK: - Preferences controller

class PreferencesController: NSObject {
    let window: NSWindow
    private let dropZone = DropZoneView(frame: .zero)
    private let pathLabel = NSTextField(labelWithString: "No selection")
    private let browseButton = NSButton(title: "Choose...", target: nil, action: nil)
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intervalLabel = NSTextField(labelWithString: "Rotate:")
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop Rotation", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let separator = NSBox()

    private var selectedPath: String?
    private var selectedIsFolder = false

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "SpanWallpaper"
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(white: 0.10, alpha: 1)

        let content = window.contentView!
        content.wantsLayer = true

        for v: NSView in [dropZone, pathLabel, browseButton, intervalLabel,
                          intervalPopup, applyButton, nextButton, stopButton,
                          statusLabel, separator] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        setupDropZone()
        setupPathRow()
        setupSeparator()
        setupIntervalRow()
        setupActionRow()
        setupStatusRow()
        layoutConstraints()

        syncUI()
    }

    private func setupDropZone() {
        dropZone.onDrop = { [weak self] url in self?.handleFile(url) }
    }

    private func setupPathRow() {
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = NSColor(white: 0.6, alpha: 1)
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.maximumNumberOfLines = 1

        browseButton.target = self
        browseButton.action = #selector(browseTapped)
        browseButton.bezelStyle = .rounded
        browseButton.controlSize = .regular
    }

    private func setupSeparator() {
        separator.boxType = .separator
    }

    private func setupIntervalRow() {
        intervalLabel.textColor = NSColor(white: 0.6, alpha: 1)
        intervalLabel.font = NSFont.systemFont(ofSize: 13)

        intervalPopup.removeAllItems()
        for preset in IntervalPreset.all {
            intervalPopup.addItem(withTitle: preset.title)
        }
        intervalPopup.selectItem(at: IntervalPreset.indexForSeconds(
            RotationManager.shared.config?.intervalSeconds ?? RotationConfig.defaultInterval
        ))
    }

    private func setupActionRow() {
        applyButton.target = self
        applyButton.action = #selector(applyTapped)
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"

        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        nextButton.bezelStyle = .rounded

        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        stopButton.bezelStyle = .rounded
        stopButton.contentTintColor = .systemRed
    }

    private func setupStatusRow() {
        statusLabel.textColor = NSColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 0.9)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
    }

    private func layoutConstraints() {
        let c = window.contentView!
        let m: CGFloat = 20

        NSLayoutConstraint.activate([
            // Drop zone
            dropZone.topAnchor.constraint(equalTo: c.topAnchor, constant: m),
            dropZone.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            dropZone.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            dropZone.heightAnchor.constraint(equalToConstant: 80),

            // Path row
            browseButton.topAnchor.constraint(equalTo: dropZone.bottomAnchor, constant: 14),
            browseButton.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            browseButton.widthAnchor.constraint(equalToConstant: 90),

            pathLabel.centerYAnchor.constraint(equalTo: browseButton.centerYAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            pathLabel.trailingAnchor.constraint(equalTo: browseButton.leadingAnchor, constant: -10),

            // Separator
            separator.topAnchor.constraint(equalTo: browseButton.bottomAnchor, constant: 14),
            separator.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            separator.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Interval row
            intervalLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 14),
            intervalLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            intervalLabel.widthAnchor.constraint(equalToConstant: 52),

            intervalPopup.centerYAnchor.constraint(equalTo: intervalLabel.centerYAnchor),
            intervalPopup.leadingAnchor.constraint(equalTo: intervalLabel.trailingAnchor, constant: 6),
            intervalPopup.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),

            // Action row
            stopButton.topAnchor.constraint(equalTo: intervalPopup.bottomAnchor, constant: 16),
            stopButton.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),

            nextButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            nextButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),

            applyButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            applyButton.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            applyButton.widthAnchor.constraint(equalToConstant: 80),

            // Status
            statusLabel.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: m),
            statusLabel.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -m),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: c.bottomAnchor, constant: -m),
        ])
    }

    func syncUI() {
        let rm = RotationManager.shared
        let rotating = rm.isActive

        if rotating, let cfg = rm.config {
            selectedPath = cfg.folderPath
            selectedIsFolder = true
            intervalPopup.selectItem(at: IntervalPreset.indexForSeconds(cfg.intervalSeconds))
        }

        if let path = selectedPath {
            let name = (path as NSString).lastPathComponent
            pathLabel.stringValue = selectedIsFolder ? "\(name)/" : name
            pathLabel.toolTip = path
        } else {
            pathLabel.stringValue = "No selection"
            pathLabel.toolTip = nil
        }

        intervalLabel.isHidden = !selectedIsFolder
        intervalPopup.isHidden = !selectedIsFolder
        nextButton.isHidden = !rotating
        stopButton.isHidden = !rotating

        applyButton.isEnabled = selectedPath != nil

        if rotating {
            let images = imageFiles(in: URL(fileURLWithPath: rm.config!.folderPath))
            let presetTitle = IntervalPreset.all[
                IntervalPreset.indexForSeconds(rm.config!.intervalSeconds)
            ].title.lowercased()
            statusLabel.stringValue = "Rotating \(images.count) images, \(presetTitle)"
            statusLabel.textColor = NSColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 0.9)
        } else {
            statusLabel.stringValue = ""
        }
    }

    func handleFile(_ url: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            let images = imageFiles(in: url)
            guard !images.isEmpty else {
                showError("No image files found in \(url.lastPathComponent).")
                return
            }
            selectedPath = url.path
            selectedIsFolder = true
            syncUI()
        } else if imageExtensions.contains(url.pathExtension.lowercased()) {
            selectedPath = url.path
            selectedIsFolder = false
            syncUI()
            applySelection()
        }
    }

    private func applySelection() {
        guard let path = selectedPath else { return }

        if selectedIsFolder {
            let images = imageFiles(in: URL(fileURLWithPath: path))
            guard !images.isEmpty else {
                showError("No image files in folder.")
                return
            }
            let idx = intervalPopup.indexOfSelectedItem
            let seconds = IntervalPreset.all[idx].seconds
            RotationManager.shared.start(folderPath: path, intervalSeconds: seconds)
            syncUI()
        } else {
            RotationManager.shared.stop()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try processImage(at: path)
                    DispatchQueue.main.async { [weak self] in
                        self?.statusLabel.stringValue = "Applied."
                        self?.statusLabel.textColor = NSColor(white: 0.5, alpha: 1)
                    }
                } catch {
                    DispatchQueue.main.async { showError(error.localizedDescription) }
                }
            }
            syncUI()
        }
    }

    // MARK: - Actions

    @objc private func browseTapped() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .folder]
        panel.message = "Choose an image or a folder of images"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleFile(url)
    }

    @objc private func applyTapped() {
        applySelection()
    }

    @objc private func nextTapped() {
        RotationManager.shared.applyNext()
        syncUI()
    }

    @objc private func stopTapped() {
        RotationManager.shared.stop()
        selectedPath = nil
        selectedIsFolder = false
        syncUI()
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var prefsController: PreferencesController?
    private var hasProcessed = false
    private var screenChangeDebounce: DispatchWorkItem?
    private var isReapplying = false

    var window: NSWindow? { prefsController?.window }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments

        if args.contains("--rotate") {
            if let config = RotationConfig.load() {
                let folder = URL(fileURLWithPath: config.folderPath)
                guard FileManager.default.isReadableFile(atPath: folder.path) else {
                    Log.info("Folder unavailable (ejected/missing?): \(config.folderPath) -- skipping tick")
                    NSApp.terminate(nil)
                    return
                }
                let images = imageFiles(in: folder)
                if let next = pickNextImage(from: images, lastUsed: config.lastImagePath) {
                    do {
                        try processImage(at: next.path)
                        var updated = config
                        updated.lastImagePath = next.path
                        updated.save()
                    } catch {
                        Log.info("ERROR: \(error)")
                    }
                }
            }
            NSApp.terminate(nil)
            return
        }

        if hasProcessed {
            NSApp.terminate(nil)
            return
        }

        let filePaths = Array(args.dropFirst()).filter { !$0.hasPrefix("-") }

        if !filePaths.isEmpty {
            hasProcessed = true
            for path in filePaths {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                if isDir.boolValue {
                    RotationManager.shared.start(folderPath: path)
                } else {
                    do { try processImage(at: path) }
                    catch { Log.info("ERROR: \(error)") }
                }
            }
            if !RotationManager.shared.isActive {
                NSApp.terminate(nil)
            }
            return
        }

        RotationManager.shared.resume()
        registerDisplayObservers()
        showPreferences()
    }

    // MARK: - Display change & wake observers

    private var spaceChangeDebounce: DispatchWorkItem?

    private func registerDisplayObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func activeSpaceChanged(_ note: Notification) {
        spaceChangeDebounce?.cancel()
        let work = DispatchWorkItem {
            guard RotationManager.shared.lastAppliedImagePath != nil else { return }
            Log.info("Space changed -- apply-only reapply")
            WallpaperSetter.reapplyLastSlices()
        }
        spaceChangeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    @objc private func screenParametersChanged(_ note: Notification) {
        screenChangeDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.debouncedReapply(reason: "screen change") }
        screenChangeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    @objc private func systemDidWake(_ note: Notification) {
        screenChangeDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.debouncedReapply(reason: "wake") }
        screenChangeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func debouncedReapply(reason: String) {
        guard !isReapplying else {
            Log.info("Re-apply already in progress, skipping (\(reason))")
            return
        }
        guard RotationManager.shared.lastAppliedImagePath != nil else { return }

        isReapplying = true
        Log.info("Re-applying wallpaper after \(reason)...")
        DispatchQueue.global(qos: .userInitiated).async {
            RotationManager.shared.reapplyCurrent()
            DispatchQueue.main.async { [weak self] in
                self?.isReapplying = false
            }
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        hasProcessed = true
        for path in filenames {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue {
                RotationManager.shared.start(folderPath: path)
                prefsController?.syncUI()
            } else {
                do {
                    try processImage(at: path)
                } catch {
                    if window != nil {
                        showError(error.localizedDescription)
                    } else {
                        Log.info("ERROR: \(error)")
                    }
                }
            }
        }
        sender.reply(toOpenOrPrint: .success)

        if window == nil && !RotationManager.shared.isActive {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !RotationManager.shared.isActive
    }

    // MARK: - Dock right-click menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard RotationManager.shared.isActive else { return nil }
        let menu = NSMenu()

        let nextItem = NSMenuItem(title: "Next Wallpaper", action: #selector(dockNextWallpaper), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Stop Rotation", action: #selector(dockStopRotation), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        return menu
    }

    @objc private func dockNextWallpaper() {
        RotationManager.shared.applyNext()
        prefsController?.syncUI()
    }

    @objc private func dockStopRotation() {
        RotationManager.shared.stop()
        if window == nil {
            NSApp.terminate(nil)
        } else {
            prefsController?.syncUI()
        }
    }

    // MARK: - Window

    private func showPreferences() {
        let pc = PreferencesController()
        self.prefsController = pc
        pc.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Helpers

func pickNextImage(from images: [URL], lastUsed: String?) -> URL? {
    guard !images.isEmpty else { return nil }
    guard let last = lastUsed,
          let idx = images.firstIndex(where: { $0.path == last }) else {
        return images.randomElement()
    }
    let nextIdx = (idx + 1) % images.count
    return images[nextIdx]
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
