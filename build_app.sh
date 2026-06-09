#!/usr/bin/env bash
# build_app.sh — assemble kcode.app: a native macOS editor for Krypton.
#
# kcode.app is a Cocoa NSTextView editor (native editing/scroll/find/undo) with
# Krypton syntax highlighting + Build via the Krypton compiler `kcc`. The window
# + text surface are Obj-C (Cocoa); the language + compiler are Krypton.
set -e
cd "$(dirname "$0")"
APP="kcode.app"
VERSION="0.3.0"

echo "==> compiling kcode-gui (native editor)"
clang -framework Cocoa -fobjc-arc -O2 -Wall gui_editor.m -o kcode-gui
codesign -s - -f kcode-gui >/dev/null 2>&1 || true

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp kcode-gui "$APP/Contents/MacOS/kcode-gui"
[ -f kcode.icns ] && cp kcode.icns "$APP/Contents/Resources/kcode.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>kcode</string>
    <key>CFBundleDisplayName</key>     <string>kcode</string>
    <key>CFBundleIdentifier</key>      <string>org.krypton-lang.kcode</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleExecutable</key>      <string>kcode-gui</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleIconFile</key>        <string>kcode</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key>          <string>Krypton source</string>
        <key>CFBundleTypeExtensions</key>    <array><string>k</string><string>ks</string><string>htk</string></array>
        <key>CFBundleTypeRole</key>          <string>Editor</string>
      </dict>
    </array>
</dict>
</plist>
PLIST

codesign --deep -s - -f "$APP" >/dev/null 2>&1 || true
echo "built $APP — open with:  open $APP"
