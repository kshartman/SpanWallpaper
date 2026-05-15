import AppKit
import SpanWallpaperLib

class AppDelegate: NSObject, NSApplicationDelegate {
    var prefsController: PreferencesController?
    private var statusBarController: StatusBarController?
    private var hasProcessed = false
    private var screenChangeDebounce: DispatchWorkItem?
    private var isReapplying = false
    private var lastLayoutFingerprint: String?

    var window: NSWindow? { prefsController?.window }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments

        if args.contains("--rotate") {
            handleRotateTick()
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
            let displayMode = AppConfig.load()?.displayMode ?? .span
            for path in filePaths {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                if isDir.boolValue {
                    RotationManager.shared.start(folderPath: path)
                } else {
                    RotationManager.shared.stop()
                    do {
                        try processImage(at: path, displayMode: displayMode)
                    } catch {
                        Log.info("ERROR: \(error)")
                    }
                }
            }
            if !RotationManager.shared.isActive {
                NSApp.terminate(nil)
            }
            return
        }

        let sbc = StatusBarController()
        sbc.onShowPreferences = { [weak self] in self?.showPreferences() }
        self.statusBarController = sbc

        RotationManager.shared.resume()
        registerDisplayObservers()
        showPreferences()
    }

    private func handleRotateTick() {
        if WallpaperSetter.consumeSkipMarker() { return }
        guard let config = AppConfig.load(), let folderPath = config.folderPath else { return }
        let folder = URL(fileURLWithPath: folderPath)
        guard FileManager.default.isReadableFile(atPath: folder.path) else {
            Log.info("Folder unavailable: \(folderPath) -- skipping tick")
            return
        }
        FolderImageCache.shared.invalidate()
        let options = ScanOptions(from: config)
        let images = imageFiles(in: folder, options: options)
        guard let next = pickNextImage(from: images, lastUsed: config.lastImagePath, playMode: config.playMode) else { return }
        do {
            try WallpaperSetter.withProcessLock {
                try processImage(at: next.path, displayMode: config.displayMode)
                var updated = config
                updated.lastImagePath = next.path
                updated.save()
            }
            WallpaperSetter.clearError()
        } catch {
            Log.info("ERROR: \(error)")
            WallpaperSetter.writeError("\(error)")
        }

        if config.autoClearCache, config.cacheAccessConfirmed, WallpaperCache.hasFDA() {
            let deleted = WallpaperCache.purge(keeping: 10)
            if deleted > 0 {
                Log.info("Purged \(deleted) macOS wallpaper cache files")
            }
        }
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
            let hasApplied = RotationManager.shared.lastAppliedImagePath != nil
            let hasSavedImage = RotationManager.shared.config?.lastImagePath != nil
                || RotationManager.shared.config?.singleImagePath != nil
            guard hasApplied || hasSavedImage else { return }

            if !WallpaperSetter.lastSliceFiles.isEmpty {
                Log.info("Space changed -- apply-only reapply")
                WallpaperSetter.reapplyLastSlices()
            } else {
                Log.info("Space changed -- full reapply")
                RotationManager.shared.reapplyCurrent()
            }
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

        if reason == "screen change" {
            if let current = try? ScreenLayout.detect().fingerprint,
               current == lastLayoutFingerprint {
                Log.info("Layout unchanged after \(reason), skipping re-render")
                return
            }
        }

        isReapplying = true
        Log.info("Re-applying wallpaper after \(reason)...")
        DispatchQueue.global(qos: .userInitiated).async {
            RotationManager.shared.reapplyCurrent()
            if let fp = try? ScreenLayout.detect().fingerprint {
                DispatchQueue.main.async { [weak self] in
                    self?.lastLayoutFingerprint = fp
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.isReapplying = false
            }
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        hasProcessed = true
        let displayMode = RotationManager.shared.config?.displayMode ?? .span
        for path in filenames {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue {
                RotationManager.shared.start(folderPath: path)
                prefsController?.syncUI()
            } else {
                RotationManager.shared.stop()
                do {
                    try processImage(at: path, displayMode: displayMode)
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
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            window?.makeKeyAndOrderFront(nil)
        } else {
            showPreferences()
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // MARK: - Window

    private func showPreferences() {
        let pc = PreferencesController()
        self.prefsController = pc
        pc.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
