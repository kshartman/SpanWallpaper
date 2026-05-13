# SpanWallpaper

Sets a single image as the macOS wallpaper, aspect-filled across all attached displays treated as one unified canvas.

## Install

```bash
./setup.sh
```

Compiles the app, generates an icon, installs to `/Applications/SpanWallpaper.app`, and creates a Desktop alias.

## Usage

- **Double-click** the app to open the preferences window
- **Drag and drop** an image onto the Desktop/Dock icon or the preferences window
- **CLI**: `open /Applications/SpanWallpaper.app --args /path/to/image.png`

### Preferences window

Double-click the app (or launch with no arguments) to open the preferences window:

- **Drop zone** -- drag an image or folder onto it
- **Choose...** -- browse for an image file or folder
- **Rotate interval** -- pick from 30 min to 1 week (shown when a folder is selected)
- **Apply** -- apply the current selection
- **Next** -- advance to the next image immediately (rotation mode)
- **Stop Rotation** -- stop rotating and uninstall the schedule

### Folder rotation

Drop or choose a folder of images to rotate the wallpaper automatically. The app picks a random image first, then cycles in sorted order. A launchd agent is installed so rotation survives reboots.

**Right-click the Dock icon** while rotation is active:
- **Next Wallpaper** -- advance immediately
- **Stop Rotation** -- stop and uninstall the schedule

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

## Requirements

- macOS 11+
- Xcode Command Line Tools (`xcode-select --install`)
