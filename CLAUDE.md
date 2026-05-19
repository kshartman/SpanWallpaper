# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SpanWallpaper -- a native macOS wallpaper manager (Swift, AppKit) with three display modes: **span** (one image across all monitors), **fit** (letterboxed per screen), and **fill** (cropped per screen). Supports folder-based rotation with shuffle/sequential play, recursive scanning with exclusion patterns, size filtering, image retirement (curation), and a launchd agent for persistence.

## Build & Run

```bash
# Full build + install to /Applications + Desktop alias
./setup.sh

# Build distributable .pkg installer (output: dist/SpanWallpaper-<version>.pkg)
./build-pkg.sh            # unsigned (dev/test)
./build-pkg.sh --sign     # Developer ID signed + notarized (release)

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
- `SpanWallpaperLib` (`Sources/SpanWallpaperLib/`) -- pure functions and shared state: `AppConfig`/`RotationConfig` (Codable, with `load()`/`save()`/`remove()`), `AppPaths` (centralized path constants), `PlayMode`, `DisplayMode`, `AppearanceMode`, `pickNextImage`, `ScanOptions`, `scanImages`, `imageDimensions`, `matchesExcludePattern`, `IntervalPreset`, `SliceFileMatch`, `imageExtensions`, `WallpaperCache` (FDA check, cache size, purge), `monitorFolders` (per-display-count folder mapping). No AppKit dependency.
- `SpanWallpaper` (`Sources/SpanWallpaper/`) -- the app, split into 8 files: `main.swift` (entry point), `AppDelegate.swift`, `ScreenLayout.swift`, `ImagePipeline.swift`, `WallpaperSetter.swift`, `Rotation.swift`, `PreferencesUI.swift`, `Utilities.swift`.
- `SpanWallpaperTests` (`Tests/SpanWallpaperTests/`) -- XCTest suite for the lib (64 tests).

Key components:

- **ScreenLayout** -- detects all displays, computes a unified point-space canvas, produces `ScreenSlice` structs with per-screen point origins and native pixel sizes. Handles mixed-DPI setups by doing layout math in points and output in pixels.
- **ImagePipeline** -- loads images via `CGImageSource` (handles EXIF orientation via CoreImage), computes aspect-fill crop rect, renders per-screen slices at native resolution, writes JPEG atomically (temp file + rename). Only used for Span mode; Fit/Fill bypass the pipeline entirely.
- **WallpaperSetter** -- applies slice files (Span) or original images (Fit/Fill) via `NSWorkspace.setDesktopImageURL`. Caches displayID-to-file mapping for fast Space-change reapply. Manages slice cleanup, cross-process locking, skip marker, and error file I/O.
- **RotationManager** -- manages folder rotation with shuffle (Fisher-Yates in-memory queue) or sequential play. Persists state to `config.json`, installs/uninstalls a launchd agent for reboot persistence. Handles retire workflow (move image to `retired/` subfolder). Supports per-display-count folder switching (`switchFolderIfNeeded`).
- **Scanner** (lib) -- configurable image scanner with recursive traversal, fnmatch-based exclusion patterns, and optional size filtering via `CGImageSourceCopyPropertiesAtIndex`.
- **PreferencesController** -- AppKit UI with drop zone, file picker, interval/play-mode/display-mode/appearance selectors, collapsible filter, cache, and displays sections, retire/next/stop buttons. Theme switcher (System/Dark/Light) via `NSAppearance`. Cache section requires FDA (Full Disk Access) to manage the macOS wallpaper cache. Displays section configures per-monitor-count folder overrides. Built programmatically (no XIB/storyboard).
- **AppDelegate** -- entry point routing: `--rotate` flag = one-shot for launchd, CLI args = direct apply, no args = show preferences. Registers observers for screen changes, wake, and Space switches to auto-reapply. Handles window reopen on dock icon click.

## Runtime Paths

- Slice storage: `~/Library/Application Support/SpanWallpaper/` (overridable via `SPAN_WALLPAPER_DIR` env var or symlink)
- Config: `~/Library/Application Support/SpanWallpaper/config.json` (auto-migrates from `rotation.json`)
- Error file: `~/Library/Application Support/SpanWallpaper/last-error.txt` (cross-process error reporting from launchd agent)
- Process lock: `~/Library/Application Support/SpanWallpaper/.lock` (flock-based)
- Skip marker: `~/Library/Application Support/SpanWallpaper/.skip-next-tick` (prevents RunAtLoad double-apply)
- LaunchAgent: `~/Library/LaunchAgents/com.shartman.SpanWallpaper.plist`
- Debug log: `~/Library/Application Support/SpanWallpaper/debug.log` (opt-in via preferences; timestamped transition log)
- Logs: stderr (or `/tmp/SpanWallpaper.log` when run via launchd)
- macOS wallpaper cache: `~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.image/` (requires FDA)

## Key Design Decisions

- Layout math uses AppKit **points** (DPI-independent) for the unified canvas; output slices use **native pixels** (`pointSize * backingScaleFactor`). This is critical for mixed-DPI multi-monitor setups.
- Wallpaper apply must happen on the **main thread** (`NSWorkspace.setDesktopImageURL` requirement). Image rendering runs on background queues.
- **Span mode** uses the full image pipeline (load, crop, slice, write JPEG, apply). **Fit/Fill modes** skip the pipeline and pass the original image directly to `NSWorkspace` with appropriate scaling options.
- Space changes use **apply-only reapply** (cached slices for Span, re-call NSWorkspace for Fit/Fill). Screen changes and wake trigger **full re-render** via `reapplyCurrent()`.
- JPEG writes are **atomic** (write to `.tmp`, then rename) to avoid corrupted wallpapers if the process is killed mid-write.
- Slice filenames use `{8-char-runID}_{displayID}.jpg` pattern. Old slices are cleaned up by regex after each apply.
- **Cross-process locking** via `flock` on all wallpaper-apply paths (`applyNext`, `applyPrevious`, `reapplyCurrent`, and the launchd `--rotate` tick) prevents the UI process and launchd agent from interleaving `NSWorkspace.setDesktopImageURL` calls.
- **Layout fingerprinting** (displayID + frame + scale) skips redundant re-renders when macOS fires screen-change notifications without actual layout changes.
- **Shuffle state is in-memory only**. Fisher-Yates shuffle queue resets on rescan, retire, play mode change, or app restart. LaunchD ticks (separate process) degrade to random selection.
- **Skip marker** (`.skip-next-tick`): written before installing the launchd agent so the `RunAtLoad` tick exits immediately without double-applying. Consumed (deleted) on read. On reboot, no marker exists, so `RunAtLoad` works normally.
- **Start order**: `RotationManager.start()` calls `applyNext()` before `installLaunchAgent()` so the first image is applied and `lastImagePath` is persisted before the agent fires.
- **Config migration**: on first v2 load, if `config.json` is missing but `rotation.json` exists, auto-migrates and deletes the old file.
- `NSWorkspace.setDesktopImageURL(_:for:options:)` is deprecated in macOS 14+. No replacement API exists yet.
- **Cache management** requires Full Disk Access (FDA) because the macOS wallpaper cache lives inside `~/Library/Containers/com.apple.wallpaper.agent/`. FDA is checked via `TCC.db` readability probe — no TCC prompt unless the user explicitly interacts with the cache section. Auto-purge only runs from the launchd `--rotate` tick, never during interactive Apply/Next/Back.
- **Code signing** (`setup.sh`) uses the first available signing identity for persistent TCC grants. Self-signed certs require manual FDA setup; Apple Developer certs auto-appear in the FDA list.
- **Appearance** uses `NSAppearance` on the window (not app-wide) with semantic AppKit colors (`.secondaryLabelColor`, `.controlBackgroundColor`, etc.) so all controls adapt automatically to System/Dark/Light. The `appearanceMode` field persists in `config.json` (backward-compatible default: `system`).
- **Config persistence lives in the lib** (`AppConfig.load()`/`save()`/`remove()` and `AppPaths`). This lets any target (app, launchd one-shot, tests) access config without going through `RotationManager`. `DebugLog` reads config from disk on each call to avoid thread-safety issues with the singleton.
- **Per-display-count folder switching**: `AppConfig.monitorFolders` maps display count ("1"/"2"/"3") to folder paths. On screen-change notification, `switchFolderIfNeeded` checks `NSScreen.screens.count`, and if an override exists for that count, switches folder, resets shuffle, applies, and reinstalls the launchd agent. The launchd `--rotate` tick also respects the mapping. Closed-laptop case is automatic — macOS only reports active displays.

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
