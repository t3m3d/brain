#!/usr/bin/env bash
# Build kcode — krypton-lang's terminal IDE.
set -e
cd "$(dirname "$0")"
# Native macho backend (kcc.sh was retired; `kcc` is the driver now).
kcc --native src/main.k -o kcode
codesign -s - -f kcode 2>/dev/null || true   # ad-hoc sign for AMFI on Tahoe
echo "built ./kcode"
