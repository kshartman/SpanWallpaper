# TODOS

## Deferred from Engineering Review (2026-05-15)

### Broader process lock scope
`RotationManager.applyNext()` in `Sources/SpanWallpaper/Rotation.swift` does not acquire the process lock. The launchd `--rotate` tick path (`handleRotateTick` in AppDelegate) does use `withProcessLock`, so collisions are prevented from that side. However, the in-process timer path in `applyNext()` is unprotected. Currently safe because the GUI timer and launchd agent rarely overlap, but a future refactor should wrap `applyNext()` in `withProcessLock` for defense in depth.

## Deferred from Engineering Review (2026-05-12)

### launchctl error handling
`RotationManager.installLaunchAgent()` / `uninstallLaunchAgent()` in `Sources/SpanWallpaper/Rotation.swift`: `launchctl bootout/bootstrap` exit codes are silently ignored (`try? proc.run()`). Should check exit status and surface failures (e.g., agent already loaded, permission denied). Low priority -- current behavior is harmless but masks configuration problems.
