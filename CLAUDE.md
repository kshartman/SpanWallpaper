# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SpanWallpaper -- a single-file native macOS app (Swift, AppKit) that spans one wallpaper image across all displays. It aspect-fills the image over the unified point-space canvas, slices it per-screen at native pixel resolution, and applies each slice via `NSWorkspace.setDesktopImageURL`. Supports folder-based rotation with a launchd agent for persistence.

## Build & Run

```bash
# Full build + install to /Applications + Desktop alias
./setup.sh

# Requires Xcode Command Line Tools (xcode-select --install)
# Compile only (no install):
swift build -c release

# Run tests:
swift test

# Run directly:
.build/release/SpanWallpaper /path/to/image.png
open /Applications/SpanWallpaper.app --args /path/to/image.png
```

SPM project with a library target (`SpanWallpaperLib`) for testable pure functions and an executable target (`SpanWallpaper`).

## Architecture

SPM package with three targets:
- `SpanWallpaperLib` (`Sources/SpanWallpaperLib/`) -- pure functions: `ImageMath.sourceFillRect`, `pickNextImage`, `RotationConfig` (Codable), `IntervalPreset`, `SliceFileMatch`, `imageExtensions`. No AppKit dependency.
- `SpanWallpaper` (`Sources/SpanWallpaper/main.swift`) -- the app. Imports the lib.
- `SpanWallpaperTests` (`Tests/SpanWallpaperTests/`) -- XCTest suite for the lib.

Key components:

- **ScreenLayout** -- detects all displays, computes a unified point-space canvas, produces `ScreenSlice` structs with per-screen point origins and native pixel sizes. Handles mixed-DPI setups by doing layout math in points and output in pixels.
- **ImagePipeline** -- loads images via `CGImageSource` (handles EXIF orientation via CoreImage), computes aspect-fill crop rect, renders per-screen slices at native resolution, writes JPEG atomically (temp file + rename).
- **WallpaperSetter** -- applies slice files via `NSWorkspace.setDesktopImageURL`, caches the displayID-to-file mapping for fast reapply on Space changes (no re-render needed), cleans up old slice files.
- **RotationManager** -- manages folder rotation: picks next image (random first, then sorted order), persists state to `rotation.json`, installs/uninstalls a launchd agent (`com.shartman.SpanWallpaper`) for reboot persistence.
- **PreferencesController** -- AppKit UI with drop zone, file picker, interval selector, and action buttons. Built programmatically (no XIB/storyboard).
- **AppDelegate** -- entry point routing: `--rotate` flag = one-shot for launchd, CLI args = direct apply, no args = show preferences. Registers observers for screen changes, wake, and Space switches to auto-reapply.

## Runtime Paths

- Slice storage: `~/Library/Application Support/SpanWallpaper/` (overridable via `SPAN_WALLPAPER_DIR` env var or symlink)
- Rotation config: `~/Library/Application Support/SpanWallpaper/rotation.json`
- LaunchAgent: `~/Library/LaunchAgents/com.shartman.SpanWallpaper.plist`
- Logs: stderr (or `/tmp/SpanWallpaper.log` when run via launchd)

## Key Design Decisions

- Layout math uses AppKit **points** (DPI-independent) for the unified canvas; output slices use **native pixels** (`pointSize * backingScaleFactor`). This is critical for mixed-DPI multi-monitor setups.
- Wallpaper apply must happen on the **main thread** (`NSWorkspace.setDesktopImageURL` requirement). Image rendering runs on background queues.
- Space changes use **apply-only reapply** (cached slices, no re-render) for speed. Screen changes and wake trigger **full re-render** via `reapplyCurrent()`.
- JPEG writes are **atomic** (write to `.tmp`, then rename) to avoid corrupted wallpapers if the process is killed mid-write.
- Slice filenames use `{8-char-runID}_{displayID}.jpg` pattern. Old slices are cleaned up by regex after each apply.
