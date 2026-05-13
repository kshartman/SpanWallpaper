import AppKit

struct ScreenSlice {
    let screen: NSScreen
    let pointOrigin: CGPoint
    let pointSize: CGSize
    let pixelSize: CGSize
    let scaleFactor: CGFloat
    let index: Int

    var displayID: CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

struct ScreenLayout {
    let slices: [ScreenSlice]
    let canvasPointSize: CGSize

    static func detect() throws -> ScreenLayout {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw WallpaperError.noScreens }

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

    var fingerprint: String {
        slices.map { s in
            "\(s.displayID):\(Int(s.pointOrigin.x)),\(Int(s.pointOrigin.y)):\(Int(s.pointSize.width))x\(Int(s.pointSize.height))@\(s.scaleFactor)"
        }.joined(separator: "|")
    }
}
