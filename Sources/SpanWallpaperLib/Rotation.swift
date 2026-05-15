import Foundation

// MARK: - Enums

public enum PlayMode: String, Codable, Equatable, CaseIterable {
    case shuffle
    case sequential
}

public enum DisplayMode: String, Codable, Equatable, CaseIterable {
    case span
    case fit
    case fill
}

// MARK: - AppConfig

public struct AppConfig: Codable, Equatable {
    public var folderPath: String?
    public var singleImagePath: String?
    public var intervalSeconds: Int
    public var playMode: PlayMode
    public var lastImagePath: String?
    public var recursive: Bool
    public var excludePatterns: [String]
    public var minWidth: Int?
    public var minHeight: Int?
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var displayMode: DisplayMode

    public static let defaultInterval = 86400

    public init(
        folderPath: String? = nil,
        singleImagePath: String? = nil,
        intervalSeconds: Int = defaultInterval,
        playMode: PlayMode = .shuffle,
        lastImagePath: String? = nil,
        recursive: Bool = true,
        excludePatterns: [String] = ["retired"],
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        displayMode: DisplayMode = .span
    ) {
        self.folderPath = folderPath
        self.singleImagePath = singleImagePath
        self.intervalSeconds = intervalSeconds
        self.playMode = playMode
        self.lastImagePath = lastImagePath
        self.recursive = recursive
        self.excludePatterns = excludePatterns
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.displayMode = displayMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folderPath = try c.decodeIfPresent(String.self, forKey: .folderPath)
        singleImagePath = try c.decodeIfPresent(String.self, forKey: .singleImagePath)
        intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? Self.defaultInterval
        playMode = try c.decodeIfPresent(PlayMode.self, forKey: .playMode) ?? .shuffle
        lastImagePath = try c.decodeIfPresent(String.self, forKey: .lastImagePath)
        recursive = try c.decodeIfPresent(Bool.self, forKey: .recursive) ?? true
        excludePatterns = try c.decodeIfPresent([String].self, forKey: .excludePatterns) ?? ["retired"]
        minWidth = try c.decodeIfPresent(Int.self, forKey: .minWidth)
        minHeight = try c.decodeIfPresent(Int.self, forKey: .minHeight)
        maxWidth = try c.decodeIfPresent(Int.self, forKey: .maxWidth)
        maxHeight = try c.decodeIfPresent(Int.self, forKey: .maxHeight)
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .span
    }
}

// Legacy type kept for migration from rotation.json
public struct RotationConfig: Codable, Equatable {
    public var folderPath: String
    public var intervalSeconds: Int
    public var lastImagePath: String?

    public static let defaultInterval = 86400

    public init(folderPath: String, intervalSeconds: Int = defaultInterval, lastImagePath: String? = nil) {
        self.folderPath = folderPath
        self.intervalSeconds = intervalSeconds
        self.lastImagePath = lastImagePath
    }

    public func toAppConfig() -> AppConfig {
        AppConfig(
            folderPath: folderPath,
            intervalSeconds: intervalSeconds,
            lastImagePath: lastImagePath
        )
    }
}

// MARK: - Interval Presets

public struct IntervalPreset: Equatable {
    public let title: String
    public let seconds: Int

    public init(title: String, seconds: Int) {
        self.title = title
        self.seconds = seconds
    }

    public static let all: [IntervalPreset] = [
        IntervalPreset(title: "Every 30 minutes", seconds: 1800),
        IntervalPreset(title: "Every hour", seconds: 3600),
        IntervalPreset(title: "Every 6 hours", seconds: 21600),
        IntervalPreset(title: "Every 12 hours", seconds: 43200),
        IntervalPreset(title: "Every day", seconds: 86400),
        IntervalPreset(title: "Every 3 days", seconds: 259200),
        IntervalPreset(title: "Every week", seconds: 604800),
    ]

    public static func indexForSeconds(_ s: Int) -> Int {
        if let exact = all.firstIndex(where: { $0.seconds == s }) { return exact }
        return all.firstIndex(where: { $0.seconds == 86400 }) ?? 4
    }
}

// MARK: - Image Selection

public func pickNextImage(from images: [URL], lastUsed: String?, playMode: PlayMode = .sequential) -> URL? {
    guard !images.isEmpty else { return nil }
    switch playMode {
    case .sequential:
        guard let last = lastUsed,
              let idx = images.firstIndex(where: { $0.path == last }) else {
            return images.randomElement()
        }
        let nextIdx = (idx + 1) % images.count
        return images[nextIdx]
    case .shuffle:
        return images.randomElement()
    }
}
