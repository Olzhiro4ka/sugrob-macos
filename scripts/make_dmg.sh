#!/usr/bin/env bash
# Packs build/Sugrob.app into a .zip and a .dmg for GitHub Releases.
# Placeholder until the release phase; currently produces the .zip only.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d build/Sugrob.app ]] || { echo "build/Sugrob.app missing; run make app" >&2; exit 1; }
ditto -c -k --keepParent build/Sugrob.app build/Sugrob.zip
echo "Built build/Sugrob.zip"
