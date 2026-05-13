# SpanWallpaper

Sets a single image as the macOS wallpaper, aspect-filled across all attached displays treated as one unified canvas.

## Install

```bash
./setup.sh
```

Compiles the app, generates an icon, installs to `/Applications/SpanWallpaper.app`, and creates a Desktop alias.

## Usage

- **Drag and drop** an image onto the Desktop/Dock icon or the app window
- **CLI**: `open /Applications/SpanWallpaper.app --args /path/to/image.png`
- **Direct**: `/Applications/SpanWallpaper.app/Contents/MacOS/SpanWallpaper /path/to/image.png`

### Folder rotation

Drop a folder of images to rotate the wallpaper automatically:

- **Drag a folder** onto the app window or Dock icon
- **CLI**: `open /Applications/SpanWallpaper.app --args /path/to/wallpapers/`

The app picks a random image immediately, then cycles through the folder in sorted order at the configured interval (default: daily). A launchd agent is installed so rotation survives reboots.

**Right-click the Dock icon** while rotation is active:
- **Next Wallpaper** -- advance immediately
- **Stop Rotation** -- stop and uninstall the schedule

Configure the interval in seconds via environment variable:

```bash
export SPAN_WALLPAPER_INTERVAL=3600   # rotate every hour
```

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
