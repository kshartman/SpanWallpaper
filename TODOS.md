# TODOS

## Deferred from Engineering Review (2026-05-12)

### launchctl error handling
`RotationManager` lines 583-598: `launchctl load/unload` exit codes are silently ignored. Should check exit status and surface failures (e.g., agent already loaded, permission denied). Low priority -- current behavior is harmless but masks configuration problems.
