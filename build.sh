#!/bin/bash
# brain — pure-Krypton macOS IDE (objk FFI). No Obj-C source.
# Build needs a Krypton checkout (compiler + stdlib + objk app packager).
set -e
KRYPTON="${KRYPTON:-$HOME/Documents/GitHub/krypton}"
[ -d "$KRYPTON/scripts" ] || { echo "set KRYPTON= to a krypton checkout"; exit 1; }
cp brain.ks brain.icns "$KRYPTON/examples/objk/"
( cd "$KRYPTON" && ./scripts/build-objk-app.sh examples/objk/brain.ks brain )
rm -rf brain.app && cp -R "$KRYPTON/dist/brain.app" .
echo "built brain.app"
