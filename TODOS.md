# TODOS

## Deferred from Engineering Review (2026-05-15)

### ~~Broader process lock scope~~
**Completed:** v2.1.2 (2026-05-15). `applyNext()` and `applyPrevious()` now wrapped in `withProcessLock`. Skip marker prevents `RunAtLoad` double-apply. Start order fixed.

## Deferred from Engineering Review (2026-05-12)

### launchctl error handling
`RotationManager.installLaunchAgent()` / `uninstallLaunchAgent()` in `Sources/SpanWallpaper/Rotation.swift`: `launchctl bootout/bootstrap` exit codes are silently ignored (`try? proc.run()`). Should check exit status and surface failures (e.g., agent already loaded, permission denied). Low priority -- current behavior is harmless but masks configuration problems.
