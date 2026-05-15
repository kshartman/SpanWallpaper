import Foundation

public let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "webp"]

public enum SliceFileMatch {
    private static let slicePattern = try! NSRegularExpression(pattern: "^[0-9A-Fa-f]{8}_\\d+\\.jpg$")
    private static let tempPattern = try! NSRegularExpression(pattern: "^\\.[0-9A-Fa-f-]+\\.tmp$")

    public static func isSliceFile(_ name: String) -> Bool {
        slicePattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    public static func isTempFile(_ name: String) -> Bool {
        tempPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    public static func shouldClean(filename: String, keeping: Set<String>) -> Bool {
        let preserve = keeping.union(["config.json", "rotation.json", "last-error.txt", ".lock"])
        if preserve.contains(filename) { return false }
        return isSliceFile(filename) || isTempFile(filename)
    }
}
