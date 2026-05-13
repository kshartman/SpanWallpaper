import AppKit
import SpanWallpaperLib

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
