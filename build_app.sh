#!/usr/bin/env bash
# build_app.sh — assemble kcode.app: a native macOS window for the kcode IDE.
#
# kcode is a pure-Krypton terminal IDE. To give it its own window (rather than
# running inside Terminal.app) it is hosted by the kryoterm terminal surface:
# the kryoterm GUI shim opens an NSWindow, the kryoterm engine runs kcode on a
# pty and renders its ANSI output. The bundle's Info.plist sets KRYOTERM_EXEC=kcode
# so the engine launches the bundled kcode instead of a shell.
set -e
cd "$(dirname "$0")"
KT="../kryoterm"            # sibling kryoterm repo (provides the engine + shim)
APP="kcode.app"
VERSION="0.3.0"

echo "==> building kcode"
./build.sh >/dev/null

echo "==> building kryoterm engine + shim"
( cd "$KT" && kcc --native run.k -o kryoterm >/dev/null 2>&1 && codesign -s - -f kryoterm >/dev/null 2>&1 && ./build_gui.sh >/dev/null && codesign -s - -f kryoterm-gui >/dev/null 2>&1 )

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$KT/kryoterm-gui" "$APP/Contents/MacOS/kcode-gui"   # the window shim (CFBundleExecutable)
cp "$KT/kryoterm"     "$APP/Contents/MacOS/kryoterm"    # the terminal engine (shim looks for this name)
cp "./kcode"          "$APP/Contents/MacOS/kcode"       # the IDE the engine runs
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
    <key>LSEnvironment</key>
    <dict>
        <key>KRYOTERM_EXEC</key>       <string>kcode</string>
    </dict>
</dict>
</plist>
PLIST

codesign --deep -s - -f "$APP" >/dev/null 2>&1 || true
echo "built $APP — open with:  open $APP"
