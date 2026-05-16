# SpanWallpaper

A native macOS wallpaper manager with three display modes: **Span** (one image across all monitors), **Fit** (letterboxed per screen), and **Fill** (cropped per screen). Supports folder-based rotation, image filtering, and wallpaper cache management.

## Install

**From .pkg (no Xcode needed):**

Download `SpanWallpaper-<version>.pkg` from Releases and double-click to install.

**From source:**

```bash
./setup.sh
```

Compiles the app, generates an icon, code-signs it, installs to `/Applications/SpanWallpaper.app`, and creates a Desktop alias.

**Build the .pkg yourself:**

```bash
./build-pkg.sh
# Output: dist/SpanWallpaper-<version>.pkg
```

## Usage

- **Double-click** the app to open the preferences window
- **Drag and drop** an image onto the Desktop/Dock icon or the preferences window
- **CLI**: `open /Applications/SpanWallpaper.app --args /path/to/image.png`

### Preferences window

Double-click the app (or click **Preferences** in the menu bar icon) to open the preferences window:

- **Drop zone** -- drag an image or folder onto it
- **Choose...** -- browse for an image file or folder
- **Rotate / Order / Display** -- interval (30 min to 1 week), shuffle or sequential, and Span/Fit/Fill mode
- **Theme** -- System, Dark, or Light appearance
- **Filters** -- collapsible section for recursive scanning, exclude patterns (glob), and min/max size constraints
- **Cache** -- collapsible section to manage macOS wallpaper cache; auto-clear on rotation or clear manually (requires Full Disk Access)
- **Displays** -- collapsible section to assign different folders per display count (1/2/3); auto-switches on dock/undock
- **Apply** -- apply the current selection
- **Next / Back** -- step forward or backward through images (rotation mode)
- **Retire** -- move current wallpaper to a `retired/` subfolder and advance
- **Stop Rotation** -- stop rotating and uninstall the schedule

### Folder rotation

Drop or choose a folder of images to rotate the wallpaper automatically. Choose shuffle or sequential play order. A launchd agent is installed so rotation survives reboots.

### Per-display folder switching

In the collapsible **Displays** section, assign different folders to 1/2/3-display configurations. When you dock, undock, or open/close the laptop lid, the app detects the new display count and switches to the matching folder automatically. Unset counts keep using the default folder.

The app runs as a **menu bar icon** (no Dock icon). Click it to access:
- **Next / Back / Retire** -- navigate or curate images
- **Preferences** -- open the full preferences window
- **Quit** -- stop the app

## Storage

Slice files are stored in `~/Library/Application Support/SpanWallpaper/`. Only the current wallpaper's slices are kept -- previous files are removed on each run.

To move storage to an external volume:

```bash
# Option 1: symlink (zero config)
rm -rf ~/Library/Application\ Support/SpanWallpaper
ln -s /Volumes/SSD/SpanWallpaper ~/Library/Application\ Support/SpanWallpaper

# Option 2: env var
export SPAN_WALLPAPER_DIR=/Volumes/SSD/SpanWallpaper
```

## Supported Formats

JPEG, PNG, HEIC, HEIF, TIFF, BMP, and WebP.

## Requirements

- macOS 11+
- Xcode Command Line Tools (`xcode-select --install`)

## Docs

- [Changelog](CHANGELOG.md)
- [Open issues](TODOS.md)
- [License (MIT)](LICENSE)
