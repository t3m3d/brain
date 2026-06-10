#!/usr/bin/env bash
set -euo pipefail

PREFIX="${1:-/usr/local}"
BIN_DIR="$PREFIX/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -x kcode ]]; then
    echo "kcode binary not found — running ./build.sh first..." >&2
    ./build.sh
fi

if [[ ! -d "$BIN_DIR" ]]; then
    echo "creating $BIN_DIR (sudo)..."
    sudo mkdir -p "$BIN_DIR"
fi

if [[ -w "$BIN_DIR" ]]; then
    ln -sf "$SCRIPT_DIR/kcode" "$BIN_DIR/kcode"
else
    sudo ln -sf "$SCRIPT_DIR/kcode" "$BIN_DIR/kcode"
fi

echo "installed:"
echo "  $BIN_DIR/kcode -> $SCRIPT_DIR/kcode"
echo
echo "try it:"
echo "  kcode $SCRIPT_DIR/src/buf.k"
