# Changelog

## 2.1.1 — 2026-05-15

Appearance switcher and UI fix.

### Features
- **Theme switcher**: choose System, Dark, or Light appearance from a segmented control in preferences -- persisted across launches

### Bug fixes
- **Cache section text now visible**: checkbox and button in the collapsible Cache section were nearly invisible against the dark background -- all UI colors now use semantic AppKit colors that adapt to any appearance

### Under the hood
- `AppearanceMode` enum in SpanWallpaperLib (system/dark/light) with `appearanceMode` field in `AppConfig` (backward-compatible default: system)
- Replaced all hardcoded `NSColor(white:)` values with semantic colors (`.secondaryLabelColor`, `.controlBackgroundColor`, `.tertiaryLabelColor`, etc.)
- Window appearance set via `NSAppearance` per-window, not app-wide

## 2.1.0 — 2026-05-15

macOS wallpaper cache management.

### Features
- **Collapsible Cache section**: manage the macOS wallpaper cache from a dedicated section in preferences (like Filters)
- **Auto-clear on rotation**: opt-in checkbox keeps only the 10 most recent cached wallpaper BMPs on each launchd rotation tick
- **Clear Cache Now**: one-click manual purge with size confirmation dialog
- **Full Disk Access flow**: guided setup prompts you to grant FDA in System Settings when first enabling cache features — one-time setup, no more per-launch permission prompts
- **Preferences on launch**: double-clicking the app always opens the preferences window
- **Code signing**: `setup.sh` now signs the app for persistent TCC grants

### Under the hood
- `WallpaperCache` module in SpanWallpaperLib with `hasFDA()`, `sizeBytes()`, `formattedSize()`, and `purge(keeping:)`
- FDA check via `TCC.db` readability probe — cache directory is never touched unless FDA is confirmed
- Auto-purge runs only from launchd `--rotate` ticks (not during interactive Apply/Next/Back) to avoid TCC prompts in the GUI
- `AppConfig` gains `autoClearCache` and `cacheAccessConfirmed` fields (backward-compatible defaults)

## 2.0.0 — 2026-05-15

Engine refactor, UI overhaul, and feature expansion.

### Features
- **Display modes**: Span (all monitors), Fit (letterbox), Fill (crop per screen)
- **Menu bar icon**: monochrome dual-monitor glyph in the system status bar; app no longer appears in Dock or Cmd-Tab (`LSUIElement`)
- **Shuffle/Sequential**: choose play order for folder rotation
- **Back button**: step backward through the sorted image list in sequential mode (full wrap-around)
- **Retire button**: move current wallpaper to a `retired/` subfolder and advance
- **Collapsible filter section**: toggle open/closed with ▶/▼ button
- **Recursive scanning**: finds images in subdirectories (default on)
- **Exclude patterns**: case-insensitive glob matching (`retired` always excluded, add comma-separated patterns)
- **Size filtering**: optional min/max width and height constraints
- **Unified config**: all settings persist in `config.json` (auto-migrates from `rotation.json`)
- **Single image tracking**: reapplies last single image on relaunch

### Bug fixes
- Clicking the app icon now reopens the preferences window when the app is already running
- Dropping an image during active rotation now stops rotation and applies immediately
- Dropping a folder now starts rotation immediately (no manual Apply needed)
- Filter text fields now save values on focus loss and before apply
- Exclude pattern matching is now case-insensitive (`FNM_CASEFOLD`)

### Under the hood
- `StatusBarController` with dynamic `NSMenu` (current image, next/previous/retire, preferences, quit)
- Collapsible filter UI with non-editable "retired" tag, separate additional patterns field
- `pickPreviousImage` pure function for deterministic backward traversal
- New `Scanner.swift` in SpanWallpaperLib with configurable recursive scanning, exclusion patterns, and size filtering
- `AppConfig` replaces `RotationConfig` with automatic migration
- Fisher-Yates shuffle with in-memory queue (degrades to random for launchd ticks)
- Fit/Fill modes bypass the slice pipeline entirely — pass original image to NSWorkspace
- 59 unit tests (up from 25) covering config, scanner, shuffle, migration, exclusion, and previous-image selection

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
