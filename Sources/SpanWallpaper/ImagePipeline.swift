import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import SpanWallpaperLib
import UniformTypeIdentifiers

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

    static func renderSlice(
        source: CGImage,
        sourceFillRect srcFill: CGRect,
        canvasPoints: CGSize,
        slice: ScreenSlice
    ) throws -> CGImage {
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

func processImage(at path: String, displayMode: DisplayMode = .span) throws {
    let inputURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL

    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw WallpaperError.imageLoadFailed(inputURL)
    }

    switch displayMode {
    case .span:
        let layout = try ScreenLayout.detect()
        Log.info("Screens: \(layout.slices.count) -- canvas \(Int(layout.canvasPointSize.width))x\(Int(layout.canvasPointSize.height))pt")
        for s in layout.slices {
            Log.info("  screen[\(s.index)] pt=(\(Int(s.pointOrigin.x)),\(Int(s.pointOrigin.y))) \(Int(s.pointSize.width))x\(Int(s.pointSize.height))pt -> \(Int(s.pixelSize.width))x\(Int(s.pixelSize.height))px @\(s.scaleFactor)x")
        }

        let source = try ImagePipeline.loadCGImage(from: inputURL)
        let sourceSize = CGSize(width: source.width, height: source.height)
        Log.info("Source: \(Int(sourceSize.width))x\(Int(sourceSize.height))px")

        let fillRect = ImageMath.sourceFillRect(sourceSize: sourceSize, canvas: layout.canvasPointSize)
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

    case .fit, .fill:
        WallpaperSetter.clearSliceCache()
        WallpaperSetter.applyOriginalToAllScreens(imageURL: inputURL, mode: displayMode)
    }

    RotationManager.shared.lastAppliedImagePath = path
    Log.info("Applied wallpaper (\(displayMode.rawValue)) across display(s).")
}
