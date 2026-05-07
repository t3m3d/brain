#!/usr/bin/env bash
# Build kcode — krypton-lang's terminal IDE.
set -e
cd "$(dirname "$0")"
kcc.sh src/main.k -o kcode
echo "built ./kcode"
