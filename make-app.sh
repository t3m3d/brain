#!/usr/bin/env bash
# make-app.sh — build a macOS .app bundle around the kcode binary.
#
# Output: dist/kcode.app
#
# Double-clicking the bundle (or `open dist/kcode.app`) launches a fresh
# Terminal.app window running kcode. Dragged-on files are passed through
# to kcode as argv. Info.plist registers the bundle as a handler for
# .k files so right-click → Open With → kcode works in Finder.
set -euo pipefail
cd "$(dirname "$0")"

[[ -x kcode ]] || ./build.sh

VERSION="0.2.0"
APP="dist/kcode.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp kcode "$APP/Contents/MacOS/kcode-bin"
chmod +x "$APP/Contents/MacOS/kcode-bin"

cat > "$APP/Contents/MacOS/kcode" <<'LAUNCHER'
#!/bin/sh
# Bundle launcher: open a fresh Terminal.app window running kcode-bin.
# Args (e.g. files dragged onto the .app icon) are forwarded via argv.
BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
KCODE_BIN="$BUNDLE_DIR/kcode-bin"

# Build the shell command we want Terminal to run.
CMD="\"$KCODE_BIN\""
for arg in "$@"; do
    CMD="$CMD \"$arg\""
done
# Run from the user's home so kcode's tree picker doesn't sit in /.
CMD="cd ~ && exec $CMD"

# Escape backslashes and double quotes for AppleScript's "..." string
# syntax — without this the literal " in $CMD terminates the string early
# and osascript fails with -2741 "Expected end of line".
APPLE_CMD=$(printf %s "$CMD" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

/usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "$APPLE_CMD"
end tell
APPLESCRIPT
LAUNCHER
chmod +x "$APP/Contents/MacOS/kcode"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>kcode</string>
    <key>CFBundleDisplayName</key>
    <string>kcode</string>
    <key>CFBundleIdentifier</key>
    <string>org.krypton-lang.kcode</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>kcode</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Krypton source file</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
                <string>public.source-code</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>k</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Plain text</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
                <string>public.text</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Macs that haven't seen this bundle yet need the Launch Services DB
# refreshed before file associations kick in. Best-effort; ignore failure.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

echo "built $APP"
echo
echo "try it:"
echo "  open $APP                 # launches kcode in a new Terminal"
echo "  open $APP src/buf.k       # opens with the file"
echo "  open -a $APP src/buf.k    # same, but force-opens with kcode"
echo
echo "to install in Applications:"
echo "  cp -R $APP /Applications/"
