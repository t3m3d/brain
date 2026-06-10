#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

MERGED="$(mktemp /tmp/kcode_merged.XXXXXX).ks"
{
  echo "// AUTO-MERGED by build.sh — edit src/*.k, not this. Single module dodges"
  echo "// the macho cross-module call relocation bug. Order: term, kv, buf, editor."
  for f in src/term.k src/kv.k src/buf.k src/editor.k; do
    grep -vE '^module |^import ' "$f"
  done
  echo ""
  echo "just run { kcodeMain() }"   # minimal entry (kcc miscompiles 2+ let in just-run)
} > "$MERGED"

kcc --native "$MERGED" -o kcode
codesign -s - -f kcode 2>/dev/null || true   # ad-hoc sign for AMFI on Tahoe
rm -f "$MERGED"
echo "built ./kcode"
