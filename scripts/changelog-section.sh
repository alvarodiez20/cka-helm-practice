#!/usr/bin/env bash
# ============================================================
#  scripts/changelog-section.sh <version>
#
#  Prints the body of one CHANGELOG entry — everything between
#  '## [X.Y.Z]' and the next '## [', with the heading and the
#  surrounding blank lines stripped.
#
#  It exists so that the release notes, the annotated tag
#  message and the GitHub Release all come from the same
#  source of truth rather than being written three times.
#
#    ./scripts/changelog-section.sh 1.10.0
# ============================================================
set -uo pipefail

VER="${1:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${CHANGELOG:-$ROOT/CHANGELOG.md}"

if [ -z "$VER" ]; then
  echo "usage: $0 <version>   e.g. $0 1.10.0" >&2
  exit 2
fi
[ -f "$LOG" ] || { echo "no CHANGELOG at $LOG" >&2; exit 2; }
grep -qF "## [${VER}]" "$LOG" || { echo "no CHANGELOG section for ${VER}" >&2; exit 1; }

# awk rather than sed, for two reasons. The range has to stop at the NEXT
# heading, and the version string contains dots that a regex would treat as
# wildcards — '1.10.0' would happily match '1x10y0'. index() compares
# literally.
#
# Blank lines are buffered rather than printed immediately, so a run of them
# at the end of the section is dropped while ones in the middle survive.
awk -v want="## [${VER}]" '
  index($0, want)==1 { inside=1; next }
  inside && index($0, "## [")==1 { exit }
  inside {
    if (NF==0) { if (started) held++; next }
    while (held-- > 0) print ""
    held = 0
    started = 1
    print
  }
' "$LOG"
