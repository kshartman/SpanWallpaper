# Changelog

## 1.0.0 — 2026-05-13

Initial release.

### Features
- Span a single wallpaper image across all connected displays with aspect-fill cropping
- Native pixel-resolution slices per screen (mixed-DPI aware)
- Folder-based rotation with configurable intervals (30 min to weekly)
- Persistent rotation via launchd agent (survives reboot/logout)
- Preferences window with drag-and-drop, file picker, and interval selector
- Dock right-click menu (Next Wallpaper, Stop Rotation)
- Auto-reapply on screen changes, wake from sleep, and Space switches
- Supports JPEG, PNG, HEIC, HEIF, TIFF, BMP, and WebP

### Architecture
- SPM package with testable library (`SpanWallpaperLib`) and executable target
- 25 unit tests covering image math, rotation logic, and file cleanup
- Cross-process file locking (flock) between UI and launchd agent
- Atomic file writes for rotation state and JPEG slices
- Layout fingerprinting to skip redundant re-renders
