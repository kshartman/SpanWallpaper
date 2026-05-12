#!/usr/bin/env swift
//
//  SpanWallpaper.swift
//
//  Native macOS app that sets a single image as the wallpaper, aspect-filled
//  across every attached display treated as one unified pixel canvas, then
//  sliced at the real pixel seams and applied per-screen.
//
//  Usage:
//      Drop an image onto the app icon, Dock icon, or window.
//      CLI:  open /Applications/SpanWallpaper.app --args /path/to/image.png
//      Direct: .../SpanWallpaper.app/Contents/MacOS/SpanWallpaper /path/to/image
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
    static let supportDir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SpanWallpaper", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func cleanCache() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) else { return }
        for url in items where url.lastPathComponent.hasPrefix("slice-") && url.pathExtension == "png" {
            try? fm.removeItem(at: url)
        }
    }

    static func apply(slices: [ScreenSlice], renderedImages: [CGImage]) throws {
        precondition(slices.count == renderedImages.count, "slice/image count mismatch")
        cleanCache()

        let runID = UUID().uuidString.prefix(8)
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue),
            .allowClipping: NSNumber(value: true)
        ]

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
        }
    }
}

// MARK: - Core processing

func processImage(at path: String) throws {
    let inputURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL

    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw WallpaperError.imageLoadFailed(inputURL)
    }

    let layout = try ScreenLayout.detect()
    Log.info("Screens: \(layout.slices.count) — canvas \(Int(layout.canvasPixelSize.width))×\(Int(layout.canvasPixelSize.height))px")
    for s in layout.slices {
        Log.info("  screen[\(s.index)] origin=(\(Int(s.pixelOrigin.x)),\(Int(s.pixelOrigin.y))) size=\(Int(s.pixelSize.width))×\(Int(s.pixelSize.height))px @\(s.screen.backingScaleFactor)x")
    }

    let source = try ImagePipeline.loadCGImage(from: inputURL)
    let sourceSize = CGSize(width: source.width, height: source.height)
    Log.info("Source: \(Int(sourceSize.width))×\(Int(sourceSize.height))px")

    let fillRect = ImagePipeline.sourceFillRect(sourceSize: sourceSize, canvas: layout.canvasPixelSize)
    Log.info("Source crop rect: \(Int(fillRect.origin.x)),\(Int(fillRect.origin.y)) \(Int(fillRect.width))×\(Int(fillRect.height))")

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

        let text = "Drop image here"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: isDragHighlighted
                ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
                : NSColor(white: 0.5, alpha: 1)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func validImageURLs(from info: NSDraggingInfo) -> [URL] {
        guard let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]
        ) as? [URL] else { return [] }
        return urls
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = validImageURLs(from: sender)
        isDragHighlighted = !urls.isEmpty
        needsDisplay = true
        return urls.isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        needsDisplay = true

        let urls = validImageURLs(from: sender)
        guard let url = urls.first else { return false }

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
        if hasProcessed {
            NSApp.terminate(nil)
            return
        }

        let args = CommandLine.arguments
        let filePaths = Array(args.dropFirst()).filter { !$0.hasPrefix("-") }

        if !filePaths.isEmpty {
            hasProcessed = true
            for path in filePaths {
                do {
                    try processImage(at: path)
                } catch {
                    Log.info("ERROR: \(error)")
                }
            }
            NSApp.terminate(nil)
            return
        }

        showDropWindow()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        hasProcessed = true
        for path in filenames {
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
        sender.reply(toOpenOrPrint: .success)

        if window == nil {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

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

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
