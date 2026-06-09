#!/usr/bin/env python3
# Re-fetch the bundled TextMate grammars (MIT, from VS Code via shiki/tm-grammars).
# Edit EXT below to add languages, then: python3 scripts/fetch_grammars.py
import urllib.request, json, os
BASE="https://raw.githubusercontent.com/shikijs/textmate-grammars-themes/main/packages/tm-grammars/grammars/"
# (the EXT map lives in git history of the first fetch; extend as needed)
