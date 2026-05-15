# Changelog

## 2.0.0 — 2026-05-14

Engine refactor and feature expansion.

### Features
- **Display modes**: Span (all monitors), Fit (letterbox), Fill (crop per screen)
- **Shuffle/Sequential**: choose play order for folder rotation
- **Retire button**: move current wallpaper to a `retired/` subfolder and advance
- **Recursive scanning**: finds images in subdirectories (default on)
- **Exclude patterns**: skip folders/files matching glob patterns (`retired` excluded by default)
- **Size filtering**: optional min/max width and height constraints
- **Unified config**: all settings persist in `config.json` (auto-migrates from `rotation.json`)
- **Single image tracking**: reapplies last single image on relaunch

### Bug fixes
- Clicking the app icon now reopens the preferences window when the app is already running
- Dropping an image during active rotation now stops rotation and applies immediately
- Dropping a folder now starts rotation immediately (no manual Apply needed)

### Under the hood
- New `Scanner.swift` in SpanWallpaperLib with configurable recursive scanning, exclusion patterns, and size filtering
- `AppConfig` replaces `RotationConfig` with automatic migration
- Fisher-Yates shuffle with in-memory queue (degrades to random for launchd ticks)
- Fit/Fill modes bypass the slice pipeline entirely — pass original image to NSWorkspace
- Dock menu gains Retire Current option
- 51 unit tests (up from 25) covering config, scanner, shuffle, migration, and exclusion patterns

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

### Under the hood
- SPM package with testable library (`SpanWallpaperLib`) and executable target
- 25 unit tests covering image math, rotation logic, and file cleanup
- Cross-process file locking (flock) between UI and launchd agent
- Atomic file writes for rotation state and JPEG slices
- Layout fingerprinting to skip redundant re-renders
