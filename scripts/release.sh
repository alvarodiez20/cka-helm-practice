#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · scripts/release.sh
#
#  Cuts a release, or checks that the last one is coherent.
#
#      ./scripts/release.sh --check          verify, change nothing
#      ./scripts/release.sh patch            1.10.0 -> 1.10.1
#      ./scripts/release.sh minor            1.10.0 -> 1.11.0
#      ./scripts/release.sh major            1.10.0 -> 2.0.0
#      ./scripts/release.sh 2.3.4            an explicit version
#      ./scripts/release.sh minor --dry-run  print the diff, write nothing
#
#  A version lives in FOUR places in this repo and they have
#  drifted apart by hand more than once:
#
#      VERSION                 read by every exam script
#      README.md               the version badge
#      CHANGELOG.md            the '## [X.Y.Z]' heading
#      git                     the annotated tag
#
#  This is the only thing that should ever change them, and
#  --check is what CI runs to prove they still agree.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";D="";BO="";N=""; fi
ok(){   printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
bad(){  printf "  ${R}✘${N} %s\n" "$*"; }
die(){  bad "$*"; exit 1; }

TODAY="$(date +%Y-%m-%d)"
REPO_URL="https://github.com/alvarodiez20/cka-helm-practice"

# ── where each version lives ────────────────────────────────
ver_file(){ tr -d '[:space:]' < VERSION 2>/dev/null; }
ver_badge(){ sed -n 's/.*version-\([0-9][0-9.]*\)-blue.*/\1/p' README.md | head -1; }
ver_changelog(){ sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG.md | head -1; }
ver_tag(){ git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//'; }

semver_ok(){ case "$1" in [0-9]*.[0-9]*.[0-9]*) [ -z "${1//[0-9.]/}" ] ;; *) return 1 ;; esac; }

# ── --check: prove the four agree ───────────────────────────
# Run by CI on every push. It deliberately does NOT require a tag to exist for
# the current version: a release commit lands before the tag is pushed, and
# failing there would block the very thing it is checking.
do_check(){
  local f b c t fail=0
  f="$(ver_file)"; b="$(ver_badge)"; c="$(ver_changelog)"; t="$(ver_tag)"

  printf "\n%s  Version consistency%s\n\n" "$BO" "$N"
  printf "    %-14s %s\n" "VERSION"      "${f:-${R}missing${N}}"
  printf "    %-14s %s\n" "README badge" "${b:-${R}missing${N}}"
  printf "    %-14s %s\n" "CHANGELOG"    "${c:-${R}missing${N}}"
  printf "    %-14s %s\n\n" "latest tag" "${t:-${D}none${N}}"

  [ -n "$f" ] || { bad "VERSION is empty or missing"; fail=1; }
  semver_ok "${f:-x}" || { bad "VERSION '$f' is not MAJOR.MINOR.PATCH"; fail=1; }
  [ "$b" = "$f" ] || { bad "README badge says '$b', VERSION says '$f'"; fail=1; }
  [ "$c" = "$f" ] || { bad "newest CHANGELOG entry is '$c', VERSION says '$f'"; fail=1; }

  # The CHANGELOG entry must have a body. An empty section means someone
  # bumped the version and forgot to say what changed, which is worse than
  # not bumping it — the tag message and the GitHub Release both come from it.
  if [ -n "$f" ]; then
    if [ -z "$("$ROOT/scripts/changelog-section.sh" "$f" 2>/dev/null)" ]; then
      bad "the CHANGELOG section for $f is empty"; fail=1
    else
      ok "CHANGELOG section for $f has content"
    fi
    if ! grep -q "^\[$f\]: " CHANGELOG.md; then
      bad "CHANGELOG has no link reference '[$f]: ...' at the bottom"; fail=1
    else
      ok "link reference for $f present"
    fi
  fi

  # Every version named by a heading should be tagged, except the current one,
  # which may legitimately be waiting for its tag to be pushed.
  local v missing=""
  for v in $(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG.md); do
    [ "$v" = "$f" ] && continue
    git rev-parse -q --verify "refs/tags/v$v" >/dev/null || missing="$missing v$v"
  done
  if [ -n "$missing" ]; then
    warn "CHANGELOG entries with no tag:$missing"
    warn "${D}the links to $REPO_URL/releases/tag/... will 404${N}"
  else
    ok "every past CHANGELOG version is tagged"
  fi

  # A tag must point at a commit whose VERSION file says the same thing.
  # Not hypothetical: a backfill script here computed the right commit for
  # each tag and then forgot to pass it to 'git tag', so all sixteen landed
  # on HEAD. Every tag existed, every link resolved, and every one of them
  # pointed at the same commit.
  local tv tc tver wrong=""
  for tv in $(git tag -l 'v[0-9]*' 2>/dev/null); do
    tc="$(git rev-list -n1 "$tv" 2>/dev/null)"
    [ -n "$tc" ] || continue
    tver="$(git show "$tc:VERSION" 2>/dev/null | tr -d '[:space:]')"
    # A tag from before the VERSION file existed has nothing to compare.
    [ -z "$tver" ] && continue
    [ "${tv#v}" = "$tver" ] || wrong="$wrong ${tv}(->${tver})"
  done
  if [ -n "$wrong" ]; then
    bad "tags pointing at a commit whose VERSION disagrees:$wrong"; fail=1
  else
    ok "every tag points at its own release commit"
  fi

  if [ "$fail" = "0" ]; then
    printf "\n  %sconsistent at %s%s\n\n" "$G$BO" "$f" "$N"; return 0
  fi
  printf "\n  %sinconsistent — fix with ./scripts/release.sh <level>%s\n\n" "$R$BO" "$N"; return 1
}

# ── the bump ────────────────────────────────────────────────
next_version(){ # <current> <major|minor|patch>
  local cur="$1" lvl="$2" MA MI PA
  MA="${cur%%.*}"; local r="${cur#*.}"; MI="${r%%.*}"; PA="${r#*.}"
  case "$lvl" in
    major) printf '%s.0.0' "$(( MA + 1 ))" ;;
    minor) printf '%s.%s.0' "$MA" "$(( MI + 1 ))" ;;
    patch) printf '%s.%s.%s' "$MA" "$MI" "$(( PA + 1 ))" ;;
  esac
}

usage(){
  sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

ARG="${1:-}"; DRY=0
case "${2:-}" in --dry-run|-n) DRY=1 ;; esac
case "$ARG" in
  ""|-h|--help|help) usage 0 ;;
  --check|check) do_check; exit $? ;;
esac

CUR="$(ver_file)"
semver_ok "$CUR" || die "VERSION does not hold a semantic version: '$CUR'"

case "$ARG" in
  major|minor|patch) NEW="$(next_version "$CUR" "$ARG")" ;;
  *) NEW="$ARG"; semver_ok "$NEW" || die "'$NEW' is not MAJOR.MINOR.PATCH, and not major/minor/patch" ;;
esac
[ "$NEW" = "$CUR" ] && die "already at $CUR"

printf "\n%s  %s → %s%s%s\n\n" "$BO" "$CUR" "$G" "$NEW" "$N"

# ── refuse to release from a state that would produce a bad tag ──
if [ "$DRY" = "0" ]; then
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
  [ -z "$(git status --porcelain -- VERSION README.md CHANGELOG.md)" ] \
    || die "VERSION, README.md or CHANGELOG.md has uncommitted changes.
      Commit or stash them first — a release commit should contain only the
      version bump, so the tag points at exactly what was released."
  git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null \
    && die "tag v$NEW already exists"
fi

# The CHANGELOG entry is written by a human, before the release. Refusing to
# invent one is deliberate: a generated entry says nothing, and this file is
# the source for the tag message and the GitHub Release both.
if ! grep -qF "## [$NEW]" CHANGELOG.md; then
  die "CHANGELOG.md has no '## [$NEW]' entry yet.

      Write it first — it becomes the annotated tag message and the body of
      the GitHub Release. Start from:

        ## [$NEW] — $TODAY

        ### Added / Changed / Fixed

        - what changed, and why it mattered
"
fi
[ -n "$("$ROOT/scripts/changelog-section.sh" "$NEW" 2>/dev/null)" ] \
  || die "the CHANGELOG section for $NEW is empty"
ok "CHANGELOG entry for $NEW found"

# ── rewrite the three files ─────────────────────────────────
apply(){
  printf '%s\n' "$NEW" > VERSION
  # Badge: only the version-X.Y.Z-blue shield, nothing else that looks like a
  # version (Kubernetes v1.35, Helm 3.x, bash 3.2 are all in there too).
  sed -i.bak "s|version-[0-9][0-9.]*-blue|version-${NEW}-blue|" README.md && rm -f README.md.bak
  # Date the entry on the day it actually ships, whatever the author wrote.
  sed -i.bak "s|^## \[${NEW}\].*|## [${NEW}] — ${TODAY}|" CHANGELOG.md && rm -f CHANGELOG.md.bak
  # And make sure the link reference exists, inserted above the newest one.
  # awk rather than 'sed i\', whose line-insert syntax differs between GNU and
  # BSD sed and would break on macOS.
  if ! grep -q "^\[${NEW}\]: " CHANGELOG.md; then
    awk -v line="[${NEW}]: ${REPO_URL}/releases/tag/v${NEW}" '
      !done && /^\[[0-9][0-9.]*\]: / { print line; done=1 }
      { print }
      END { if (!done) { print ""; print line } }
    ' CHANGELOG.md > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md
  fi
}

if [ "$DRY" = "1" ]; then
  warn "dry run — showing what would change, writing nothing"
  cp VERSION /tmp/.rel.VERSION; cp README.md /tmp/.rel.README; cp CHANGELOG.md /tmp/.rel.CHANGELOG
  apply
  git --no-pager diff --stat -- VERSION README.md CHANGELOG.md
  git --no-pager diff -- VERSION README.md | sed 's/^/    /'
  cp /tmp/.rel.VERSION VERSION; cp /tmp/.rel.README README.md; cp /tmp/.rel.CHANGELOG CHANGELOG.md
  rm -f /tmp/.rel.VERSION /tmp/.rel.README /tmp/.rel.CHANGELOG
  printf "\n  %snothing was written%s\n\n" "$D" "$N"
  exit 0
fi

apply
ok "VERSION, README badge and CHANGELOG heading set to $NEW"

# --cleanup=verbatim, because CHANGELOG sections are markdown and git's
# default cleanup strips every line starting with '#' as a comment. Without
# it the '### Fixed' and '### Added' headings vanish from the tag message and
# from the GitHub Release built out of it — which is exactly what the first
# run of this script did.
git add VERSION README.md CHANGELOG.md
printf 'Release %s\n\n%s\n' "$NEW" "$("$ROOT/scripts/changelog-section.sh" "$NEW" | head -20)" \
  | git commit -q --cleanup=verbatim -F - \
  || die "the release commit failed"
ok "release commit created"

printf 'v%s\n\n%s\n' "$NEW" "$("$ROOT/scripts/changelog-section.sh" "$NEW")" \
  | git tag -a "v$NEW" --cleanup=verbatim -F - \
  || die "could not create the tag"
ok "annotated tag v$NEW created"

do_check || warn "post-release check reported problems — look above"

printf "\n  %sPush it, tag included — the release workflow fires on the tag:%s\n\n" "$BO" "$N"
printf "      git push && git push origin v%s\n\n" "$NEW"
