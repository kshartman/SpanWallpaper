import AppKit
import SpanWallpaperLib

class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    var onShowPreferences: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeStatusIcon()
            button.image?.isTemplate = true
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let rm = RotationManager.shared
        let rotating = rm.isActive
        let sequential = rm.config?.playMode == .sequential

        if let imagePath = rm.lastAppliedImagePath ?? rm.config?.lastImagePath {
            let name = (imagePath as NSString).lastPathComponent
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = imagePath
            menu.addItem(item)
            menu.addItem(NSMenuItem.separator())
        }

        let nextItem = NSMenuItem(title: "Next Wallpaper", action: #selector(nextWallpaper), keyEquivalent: "")
        nextItem.target = self
        nextItem.isEnabled = rotating
        menu.addItem(nextItem)

        if sequential {
            let prevItem = NSMenuItem(title: "Previous Wallpaper", action: #selector(previousWallpaper), keyEquivalent: "")
            prevItem.target = self
            prevItem.isEnabled = rotating
            menu.addItem(prevItem)
        }

        let retireItem = NSMenuItem(title: "Retire Current", action: #selector(retireCurrent), keyEquivalent: "")
        retireItem.target = self
        retireItem.isEnabled = rotating
        menu.addItem(retireItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        if rotating {
            let stopItem = NSMenuItem(title: "Stop Rotation", action: #selector(stopRotation), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SpanWallpaper", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func nextWallpaper() {
        RotationManager.shared.applyNext()
        NotificationCenter.default.post(name: .spanWallpaperSyncUI, object: nil)
    }

    @objc private func previousWallpaper() {
        RotationManager.shared.applyPrevious()
        NotificationCenter.default.post(name: .spanWallpaperSyncUI, object: nil)
    }

    @objc private func retireCurrent() {
        RotationManager.shared.retireCurrent()
        NotificationCenter.default.post(name: .spanWallpaperSyncUI, object: nil)
    }

    @objc private func showPreferences() {
        onShowPreferences?()
    }

    @objc private func stopRotation() {
        RotationManager.shared.stop()
        NotificationCenter.default.post(name: .spanWallpaperSyncUI, object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private static func makeStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let monW: CGFloat = 7.5
            let monH: CGFloat = 5.5
            let gap: CGFloat = 1.5
            let totalW = monW * 2 + gap
            let originX = (rect.width - totalW) / 2
            let originY: CGFloat = 5.5

            ctx.setLineWidth(1.0)
            ctx.setStrokeColor(NSColor.black.cgColor)

            let left = CGRect(x: originX, y: originY, width: monW, height: monH)
            ctx.addRect(left)
            ctx.strokePath()

            let right = CGRect(x: originX + monW + gap, y: originY, width: monW, height: monH)
            ctx.addRect(right)
            ctx.strokePath()

            let standY = originY - 2
            for midX in [left.midX, right.midX] {
                ctx.move(to: CGPoint(x: midX, y: originY))
                ctx.addLine(to: CGPoint(x: midX, y: standY))
                ctx.strokePath()
                ctx.move(to: CGPoint(x: midX - 2.5, y: standY))
                ctx.addLine(to: CGPoint(x: midX + 2.5, y: standY))
                ctx.strokePath()
            }

            return true
        }
        return image
    }
}

extension Notification.Name {
    static let spanWallpaperSyncUI = Notification.Name("spanWallpaperSyncUI")
}
