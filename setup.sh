#!/usr/bin/env bash
#
# setup.sh — Build, bundle, and install SpanWallpaper.app
#
# Compiles the native Swift app, generates an icon, installs to /Applications,
# and drops a Finder alias on the Desktop.
#
# Usage:  ./setup.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SpanWallpaper"
APP="/Applications/$APP_NAME.app"

WORK="$(mktemp -d -t spanwallpaper-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

for tool in /usr/bin/swift /usr/bin/sips /usr/bin/iconutil; do
    [[ -x "$tool" ]] || { echo "Missing: $tool" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1) Compile via SPM
# ---------------------------------------------------------------------------
echo "Compiling..."
(cd "$SCRIPT_DIR" && /usr/bin/swift build -c release 2>&1)
SPM_BIN="$SCRIPT_DIR/.build/release/$APP_NAME"
[[ -x "$SPM_BIN" ]] || { echo "Build failed: $SPM_BIN not found" >&2; exit 1; }
cp "$SPM_BIN" "$WORK/$APP_NAME"
echo "Built binary: $WORK/$APP_NAME"

# ---------------------------------------------------------------------------
# 2) Create .app bundle
# ---------------------------------------------------------------------------
BUNDLE="$WORK/$APP_NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp "$WORK/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SpanWallpaper</string>
    <key>CFBundleIdentifier</key>
    <string>com.shartman.SpanWallpaper</string>
    <key>CFBundleName</key>
    <string>SpanWallpaper</string>
    <key>CFBundleDisplayName</key>
    <string>SpanWallpaper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Folder</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.folder</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
PLIST_EOF

# ---------------------------------------------------------------------------
# 3) Generate icon
# ---------------------------------------------------------------------------
echo "Generating icon..."
ICON_SWIFT="$WORK/MakeIcon.swift"
ICON_1024="$WORK/icon_1024.png"

cat > "$ICON_SWIFT" <<'SWIFT_EOF'
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: MakeIcon <out.png>\n".utf8))
    exit(64)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(2) }

let inset: CGFloat = 80
let bgRect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: 200, cornerHeight: 200, transform: nil))
ctx.clip()
let bgGrad = CGGradient(colorsSpace: cs,
    colors: [
        CGColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 1.0),
        CGColor(red: 0.12, green: 0.20, blue: 0.36, alpha: 1.0)
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bgGrad,
    start: CGPoint(x: S/2, y: inset),
    end:   CGPoint(x: S/2, y: S - inset),
    options: [])
ctx.restoreGState()

let totalW: CGFloat = S * 0.62
let monH:   CGFloat = totalW * 0.36
let gap:    CGFloat = 16
let monW    = (totalW - gap) / 2
let originX = (S - totalW) / 2
let originY = (S - monH) / 2 - 30

let leftScreen  = CGRect(x: originX,              y: originY, width: monW, height: monH)
let rightScreen = CGRect(x: originX + monW + gap, y: originY, width: monW, height: monH)

func drawBezel(around screen: CGRect) {
    let bezel = screen.insetBy(dx: -10, dy: -10)
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0))
    ctx.addPath(CGPath(roundedRect: bezel, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}
drawBezel(around: leftScreen)
drawBezel(around: rightScreen)

func drawSliceInto(_ screenRect: CGRect, sliceOffsetX: CGFloat) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.clip()
    let skyGrad = CGGradient(colorsSpace: cs,
        colors: [
            CGColor(red: 0.99, green: 0.78, blue: 0.45, alpha: 1.0),
            CGColor(red: 0.55, green: 0.45, blue: 0.80, alpha: 1.0),
            CGColor(red: 0.12, green: 0.16, blue: 0.40, alpha: 1.0)
        ] as CFArray,
        locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(skyGrad,
        start: CGPoint(x: screenRect.midX, y: screenRect.minY),
        end:   CGPoint(x: screenRect.midX, y: screenRect.maxY),
        options: [])
    let combinedOriginX = screenRect.minX - sliceOffsetX
    let canvasMidX = combinedOriginX + totalW/2
    let horizonY   = originY + monH * 0.42
    let sunR: CGFloat = monH * 0.20
    ctx.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.62, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: canvasMidX - sunR, y: horizonY - sunR,
                               width: 2*sunR, height: 2*sunR))
    let mtnBase = originY + monH * 0.30
    let peaks: [(CGFloat, CGFloat)] = [
        (0.00, 0.04), (0.12, 0.14), (0.22, 0.07), (0.34, 0.18),
        (0.48, 0.10), (0.58, 0.22), (0.71, 0.09), (0.84, 0.16), (1.00, 0.06)
    ]
    let path = CGMutablePath()
    path.move(to: CGPoint(x: combinedOriginX, y: mtnBase))
    for (xFrac, hFrac) in peaks {
        path.addLine(to: CGPoint(x: combinedOriginX + totalW * xFrac,
                                 y: mtnBase + monH * hFrac))
    }
    path.addLine(to: CGPoint(x: combinedOriginX + totalW, y: mtnBase))
    path.closeSubpath()
    ctx.setFillColor(CGColor(red: 0.10, green: 0.16, blue: 0.30, alpha: 1.0))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.setFillColor(CGColor(red: 0.04, green: 0.08, blue: 0.16, alpha: 1.0))
    ctx.fill(CGRect(x: screenRect.minX, y: screenRect.minY,
                    width: screenRect.width, height: monH * 0.18))
    ctx.restoreGState()
}
drawSliceInto(leftScreen,  sliceOffsetX: 0)
drawSliceInto(rightScreen, sliceOffsetX: monW + gap)

ctx.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0))
for screen in [leftScreen, rightScreen] {
    let neckW: CGFloat = 22; let neckH: CGFloat = 46
    let baseW: CGFloat = 130; let baseH: CGFloat = 12
    ctx.fill(CGRect(x: screen.midX - neckW/2, y: screen.minY - neckH, width: neckW, height: neckH))
    ctx.fill(CGRect(x: screen.midX - baseW/2, y: screen.minY - neckH - baseH, width: baseW, height: baseH))
}

guard let cgImg = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(3) }
CGImageDestinationAddImage(dest, cgImg, nil)
guard CGImageDestinationFinalize(dest) else { exit(4) }
SWIFT_EOF

/usr/bin/swift "$ICON_SWIFT" "$ICON_1024"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    s2=$((s * 2))
    /usr/bin/sips -z "$s"  "$s"  "$ICON_1024" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
    /usr/bin/sips -z "$s2" "$s2" "$ICON_1024" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
echo "Icon installed."

# ---------------------------------------------------------------------------
# 4) Install to /Applications
# ---------------------------------------------------------------------------
if pgrep -f "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    echo "Quitting running instance..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    pkill -f "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi
if [[ -d "$APP" ]]; then
    echo "Removing old $APP..."
    rm -rf "$APP"
fi
cp -R "$BUNDLE" "$APP"
touch "$APP"
echo "Installed: $APP"

# Register with LaunchServices
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [[ -x "$LSREG" ]]; then
    "$LSREG" -f "$APP" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 5) Desktop alias
# ---------------------------------------------------------------------------
/usr/bin/osascript >/dev/null <<APPLESCRIPT_EOF
on run
    tell application "Finder"
        set targetFile to POSIX file "$APP" as alias
        repeat with n in {"$APP_NAME", "$APP_NAME.app", "$APP_NAME alias"}
            try
                delete (every item of desktop whose name is (n as text))
            end try
        end repeat
        set newAlias to make new alias file at desktop to targetFile
        try
            set name of newAlias to "$APP_NAME"
        end try
    end tell
end run
APPLESCRIPT_EOF
echo "Desktop alias created."

# Refresh Dock so icon appears correctly
killall Dock >/dev/null 2>&1 || true

echo ""
echo "Done. Drop an image onto SpanWallpaper on your Desktop or Dock."
