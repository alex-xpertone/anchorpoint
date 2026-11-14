#!/usr/bin/env bash
# AnchorPoint Mesh — compile every *.d2 under deployments/ to SVG.
#   scripts/render-diagrams.sh              # all
#   scripts/render-diagrams.sh path/to.d2   # one
#   FORMAT=png scripts/render-diagrams.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMAT="${FORMAT:-svg}"
command -v d2 >/dev/null 2>&1 || { echo "d2 not found: brew install d2" >&2; exit 1; }
one() { echo "  d2 $1 -> ${1%.d2}.${FORMAT}"; d2 --theme "${D2_THEME:-0}" "$1" "${1%.d2}.${FORMAT}"; }
if [[ $# -ge 1 ]]; then one "$1"; else
  found=0
  while IFS= read -r -d '' f; do found=1; one "$f"; done < <(find "$REPO/deployments" -name '*.d2' -print0)
  [[ "$found" -eq 0 ]] && echo "No .d2 files under deployments/."
fi
echo "Done."
