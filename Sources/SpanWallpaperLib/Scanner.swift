import Foundation
import ImageIO

public struct ScanOptions: Equatable {
    public var recursive: Bool
    public var excludePatterns: [String]
    public var minWidth: Int?
    public var minHeight: Int?
    public var maxWidth: Int?
    public var maxHeight: Int?

    public init(
        recursive: Bool = true,
        excludePatterns: [String] = ["retired"],
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) {
        self.recursive = recursive
        self.excludePatterns = excludePatterns
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }

    public init(from config: AppConfig) {
        self.recursive = config.recursive
        self.excludePatterns = config.excludePatterns
        self.minWidth = config.minWidth
        self.minHeight = config.minHeight
        self.maxWidth = config.maxWidth
        self.maxHeight = config.maxHeight
    }

    public var hasSizeFilter: Bool {
        minWidth != nil || minHeight != nil || maxWidth != nil || maxHeight != nil
    }
}

public func scanImages(in folder: URL, options: ScanOptions) -> [URL] {
    let fm = FileManager.default
    var enumeratorOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    if !options.recursive {
        enumeratorOptions.insert(.skipsSubdirectoryDescendants)
    }

    guard let enumerator = fm.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: enumeratorOptions
    ) else { return [] }

    var images: [URL] = []

    for case let url as URL in enumerator {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues?.isDirectory == true {
            if matchesExcludePattern(url.lastPathComponent, patterns: options.excludePatterns) {
                enumerator.skipDescendants()
            }
            continue
        }

        guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }

        if matchesExcludePattern(url.lastPathComponent, patterns: options.excludePatterns) {
            continue
        }

        if options.hasSizeFilter {
            guard let (w, h) = imageDimensions(at: url) else { continue }
            if let min = options.minWidth, w < min { continue }
            if let min = options.minHeight, h < min { continue }
            if let max = options.maxWidth, w > max { continue }
            if let max = options.maxHeight, h > max { continue }
        }

        images.append(url)
    }

    return images.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
}

public func matchesExcludePattern(_ name: String, patterns: [String]) -> Bool {
    for pattern in patterns {
        if fnmatch(pattern, name, 0) == 0 { return true }
    }
    return false
}

public func imageDimensions(at url: URL) -> (width: Int, height: Int)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
    guard let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (w, h)
}
