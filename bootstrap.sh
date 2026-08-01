#!/usr/bin/env bash
# Downloads the exams and prepares the environment in one go.
#   curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-helm-practice/main/bootstrap.sh | bash
#
# By default it seeds exam 1. To seed another instead:
#   curl -sL .../bootstrap.sh | EXAM=2 bash
#   curl -sL .../bootstrap.sh | EXAM=3 bash
#   curl -sL .../bootstrap.sh | EXAM=4 bash
#   curl -sL .../bootstrap.sh | EXAM=5 bash    <- breaks a worker node
#   curl -sL .../bootstrap.sh | EXAM=6 bash    <- breaks kube-scheduler
#   curl -sL .../bootstrap.sh | EXAM=7 bash
#   curl -sL .../bootstrap.sh | EXAM=8 bash
#   curl -sL .../bootstrap.sh | EXAM=9 bash
set -uo pipefail

GH_USER="${GH_USER:-alvarodiez20}"
BRANCH="${GH_BRANCH:-main}"
EXAM="${EXAM:-1}"
RAW="https://raw.githubusercontent.com/${GH_USER}/cka-helm-practice/${BRANCH}"
DEST="${HOME}/cka-helm-practice"

echo
echo "  Downloading cka-helm-practice from ${GH_USER}..."
mkdir -p "$DEST" && cd "$DEST" || exit 1

# Fetch everything, but do NOT abort the whole install because one file is
# missing. A single 404 — a partial push, a renamed file, or just CDN lag
# right after a release — used to leave you with a half-populated directory
# and no working exams at all. Missing files are reported; the install only
# fails if the exam you actually asked for is not there.
FILES="setup.sh exam.sh setup2.sh exam2.sh setup3.sh exam3.sh
setup4.sh exam4.sh setup5.sh exam5.sh setup6.sh exam6.sh
setup7.sh exam7.sh setup8.sh exam8.sh setup9.sh exam9.sh
cka.sh activate.sh VERSION"

MISSING=""
for f in $FILES; do
  curl -fsSL "${RAW}/${f}" -o "$f" 2>/dev/null || MISSING="$MISSING $f"
done
chmod +x ./*.sh 2>/dev/null

if [ -n "$MISSING" ]; then
  echo
  echo "  warning: could not download:$MISSING"
  echo "  (everything else installed; those exams will be unavailable)"
fi

# The one thing worth failing over: the exam that was actually requested.
case "$EXAM" in
  1|"") NEED="setup.sh exam.sh" ;;
  *)    NEED="setup${EXAM}.sh exam${EXAM}.sh" ;;
esac
for f in $NEED; do
  [ -s "$f" ] || { echo "  cannot start exam ${EXAM}: ${f} is missing"; exit 1; }
done

case "$EXAM" in
  2) exec ./setup2.sh ;;
  3) exec ./setup3.sh ;;
  4) exec ./setup4.sh ;;
  5) exec ./setup5.sh ;;
  6) exec ./setup6.sh ;;
  7) exec ./setup7.sh ;;
  8) exec ./setup8.sh ;;
  9) exec ./setup9.sh ;;
  *) exec ./setup.sh ;;
esac
