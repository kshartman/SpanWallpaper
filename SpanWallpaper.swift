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
    let pixelOrigin: CGPoint
    let pixelSize: CGSize
    let index: Int
}

struct ScreenLayout {
    let slices: [ScreenSlice]
    let canvasPixelSize: CGSize

    static func detect() throws -> ScreenLayout {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw WallpaperError.noScreens }

        struct Raw { let screen: NSScreen; let pxRect: CGRect }
        let raws: [Raw] = screens.map { s in
            let scale = s.backingScaleFactor
            let f = s.frame
            return Raw(screen: s, pxRect: CGRect(
                x: f.origin.x * scale,
                y: f.origin.y * scale,
                width: f.size.width * scale,
                height: f.size.height * scale
            ))
        }

        let minX = raws.map { $0.pxRect.minX }.min()!
        let maxX = raws.map { $0.pxRect.maxX }.max()!
        let minY = raws.map { $0.pxRect.minY }.min()!
        let maxY = raws.map { $0.pxRect.maxY }.max()!

        let canvas = CGSize(width: maxX - minX, height: maxY - minY)

        let ordered = raws.sorted {
            $0.pxRect.minX != $1.pxRect.minX
                ? $0.pxRect.minX < $1.pxRect.minX
                : $0.pxRect.minY < $1.pxRect.minY
        }

        let slices: [ScreenSlice] = ordered.enumerated().map { (i, r) in
            let px = r.pxRect.minX - minX
            let py = maxY - r.pxRect.maxY
            return ScreenSlice(
                screen: r.screen,
                pixelOrigin: CGPoint(x: px, y: py),
                pixelSize: r.pxRect.size,
                index: i
            )
        }

        return ScreenLayout(slices: slices, canvasPixelSize: canvas)
    }
}

// MARK: - Image pipeline

enum ImagePipeline {

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
        let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])
        guard let baked = ctx.createCGImage(ci, from: ci.extent) else {
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

    static func renderSlice(
        source: CGImage,
        sourceFillRect srcFill: CGRect,
        canvas: CGSize,
        slice: ScreenSlice
    ) throws -> CGImage {
        let sx = srcFill.width / canvas.width
        let sy = srcFill.height / canvas.height
        let srcRect = CGRect(
            x: srcFill.origin.x + slice.pixelOrigin.x * sx,
            y: srcFill.origin.y + slice.pixelOrigin.y * sy,
            width: slice.pixelSize.width * sx,
            height: slice.pixelSize.height * sy
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

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw WallpaperError.writeFailed(url, underlying: NSError(
                domain: "SpanWallpaper", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CGImageDestination init failed"]
            ))
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw WallpaperError.writeFailed(url, underlying: NSError(
                domain: "SpanWallpaper", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "CGImageDestination finalize failed"]
            ))
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

    static func apply(slices: [ScreenSlice], renderedImages: [CGImage]) throws {
        precondition(slices.count == renderedImages.count, "slice/image count mismatch")

        let fm = FileManager.default
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue),
            .allowClipping: NSNumber(value: true)
        ]

        let runID = UUID().uuidString.prefix(8)
        var written: [URL] = []
        for (slice, image) in zip(slices, renderedImages) {
            let url = supportDir.appendingPathComponent(
                "slice-\(slice.index)-\(runID).png", isDirectory: false
            )
            try ImagePipeline.writePNG(image, to: url)
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: slice.screen, options: options)
            } catch {
                throw WallpaperError.setWallpaperFailed(screenIndex: slice.index, underlying: error)
            }
            written.append(url)
        }

        // Remove old slices only (preserve rotation.json)
        let keep = Set(written.map { $0.lastPathComponent } + ["rotation.json"])
        if let items = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
            for url in items where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
    }
}

// MARK: - Folder scanning

let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "webp"]

func imageFiles(in folderURL: URL) -> [URL] {
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
        RotationConfig.remove()
        uninstallLaunchAgent()
        Log.info("Rotation stopped.")
    }

    func applyNext() {
        guard let config = config else { return }
        let folder = URL(fileURLWithPath: config.folderPath)
        let images = imageFiles(in: folder)
        guard !images.isEmpty else {
            Log.info("No images in \(config.folderPath)")
            return
        }

        let next = pickNext(from: images, lastUsed: config.lastImagePath)
        do {
            try processImage(at: next.path)
            self.config?.lastImagePath = next.path
            self.config?.save()
        } catch {
            Log.info("Rotation error: \(error)")
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

    private func installLaunchAgent() {
        guard let config = config else { return }
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
                <string>\(appBinaryPath)</string>
                <string>--rotate</string>
            </array>
            <key>StartInterval</key>
            <integer>\(config.intervalSeconds)</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/tmp/SpanWallpaper.log</string>
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
    Log.info("Screens: \(layout.slices.count) -- canvas \(Int(layout.canvasPixelSize.width))x\(Int(layout.canvasPixelSize.height))px")
    for s in layout.slices {
        Log.info("  screen[\(s.index)] origin=(\(Int(s.pixelOrigin.x)),\(Int(s.pixelOrigin.y))) size=\(Int(s.pixelSize.width))x\(Int(s.pixelSize.height))px @\(s.screen.backingScaleFactor)x")
    }

    let source = try ImagePipeline.loadCGImage(from: inputURL)
    let sourceSize = CGSize(width: source.width, height: source.height)
    Log.info("Source: \(Int(sourceSize.width))x\(Int(sourceSize.height))px")

    let fillRect = ImagePipeline.sourceFillRect(sourceSize: sourceSize, canvas: layout.canvasPixelSize)
    Log.info("Source crop rect: \(Int(fillRect.origin.x)),\(Int(fillRect.origin.y)) \(Int(fillRect.width))x\(Int(fillRect.height))")

    let rendered: [CGImage] = try layout.slices.map { slice in
        try ImagePipeline.renderSlice(
            source: source,
            sourceFillRect: fillRect,
            canvas: layout.canvasPixelSize,
            slice: slice
        )
    }

    try WallpaperSetter.apply(slices: layout.slices, renderedImages: rendered)
    Log.info("Applied wallpaper across \(layout.slices.count) display(s).")
}

func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "SpanWallpaper"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.runModal()
}

// MARK: - Drop target view

class DropTargetView: NSView {
    private var isDragHighlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isDragHighlighted
            ? NSColor(white: 0.15, alpha: 1)
            : NSColor(white: 0.10, alpha: 1)
        bg.setFill()
        dirtyRect.fill()

        let inset = bounds.insetBy(dx: 24, dy: 24)
        let dash: NSBezierPath = NSBezierPath(roundedRect: inset, xRadius: 16, yRadius: 16)
        dash.lineWidth = 3
        let pattern: [CGFloat] = [8, 6]
        dash.setLineDash(pattern, count: 2, phase: 0)
        let strokeColor: NSColor = isDragHighlighted
            ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.9)
            : NSColor(white: 0.35, alpha: 1)
        strokeColor.setStroke()
        dash.stroke()

        let mainText = "Drop image or folder"
        let subText = RotationManager.shared.isActive
            ? "Rotating: \(RotationManager.shared.folderName ?? "?")"
            : "Folder = rotate daily"

        let mainAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: isDragHighlighted
                ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
                : NSColor(white: 0.5, alpha: 1)
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: RotationManager.shared.isActive
                ? NSColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 0.8)
                : NSColor(white: 0.35, alpha: 1)
        ]

        let mainSize = (mainText as NSString).size(withAttributes: mainAttrs)
        let subSize = (subText as NSString).size(withAttributes: subAttrs)
        let gap: CGFloat = 6
        let totalH = mainSize.height + gap + subSize.height
        let topY = bounds.midY + totalH / 2 - mainSize.height

        (mainText as NSString).draw(
            at: CGPoint(x: bounds.midX - mainSize.width / 2, y: topY),
            withAttributes: mainAttrs
        )
        (subText as NSString).draw(
            at: CGPoint(x: bounds.midX - subSize.width / 2, y: topY - gap - subSize.height),
            withAttributes: subAttrs
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

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            let images = imageFiles(in: url)
            guard !images.isEmpty else {
                showError("No image files found in \(url.lastPathComponent).")
                return false
            }

            let interval: Int
            if let envVal = ProcessInfo.processInfo.environment["SPAN_WALLPAPER_INTERVAL"],
               let parsed = Int(envVal), parsed > 0 {
                interval = parsed
            } else {
                interval = RotationConfig.defaultInterval
            }

            RotationManager.shared.start(folderPath: url.path, intervalSeconds: interval)
            needsDisplay = true
            return true
        }

        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return false }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try processImage(at: url.path)
            } catch {
                DispatchQueue.main.async { showError(error.localizedDescription) }
            }
        }
        return true
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var hasProcessed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments

        // launchd invokes with --rotate: apply next from saved config and exit
        if args.contains("--rotate") {
            if let config = RotationConfig.load() {
                let folder = URL(fileURLWithPath: config.folderPath)
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

        // Resume rotation if config exists
        RotationManager.shared.resume()

        showDropWindow()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        hasProcessed = true
        for path in filenames {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue {
                RotationManager.shared.start(folderPath: path)
                if let w = window {
                    w.contentView?.needsDisplay = true
                }
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
    }

    @objc private func dockStopRotation() {
        RotationManager.shared.stop()
        if window == nil {
            NSApp.terminate(nil)
        } else {
            window?.contentView?.needsDisplay = true
        }
    }

    // MARK: - Window

    private func showDropWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "SpanWallpaper"
        w.center()
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(white: 0.10, alpha: 1)
        w.contentView = DropTargetView(frame: w.contentView!.bounds)
        w.contentView?.autoresizingMask = [.width, .height]
        w.makeKeyAndOrderFront(nil)
        self.window = w

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
