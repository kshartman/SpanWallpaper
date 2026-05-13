import Foundation

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
}

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

public func pickNextImage(from images: [URL], lastUsed: String?) -> URL? {
    guard !images.isEmpty else { return nil }
    guard let last = lastUsed,
          let idx = images.firstIndex(where: { $0.path == last }) else {
        return images.randomElement()
    }
    let nextIdx = (idx + 1) % images.count
    return images[nextIdx]
}
