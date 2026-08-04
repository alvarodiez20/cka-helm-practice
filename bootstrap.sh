#!/usr/bin/env bash
# Downloads the exams and prepares the environment in one go.
#   curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-practice/main/bootstrap.sh | bash
#
# Every exam is installed either way. EXAM only decides which one is SEEDED —
# built in the cluster — before you are handed the prompt. Since 'cka use
# <name>' seeds an exam on selection, this is a convenience, not a
# requirement: it exists so you can skip building an exam you did not want.
#
#   curl -sL .../bootstrap.sh | bash              seeds exam 1 (default)
#   curl -sL .../bootstrap.sh | EXAM=7 bash       seeds storage instead
#   curl -sL .../bootstrap.sh | EXAM=none bash    installs, seeds nothing
#
# EXAM=5 breaks a worker node, EXAM=6 breaks kube-scheduler, and EXAM=10
# disables a worker's CNI — all on purpose.
set -uo pipefail

GH_USER="${GH_USER:-alvarodiez20}"
BRANCH="${GH_BRANCH:-main}"
EXAM="${EXAM:-1}"
COUNT="${CKA_EXAM_COUNT:-11}"
RAW="https://raw.githubusercontent.com/${GH_USER}/cka-practice/${BRANCH}"
DEST="${HOME}/cka-practice"

echo
echo "  Downloading cka-practice from ${GH_USER}..."
mkdir -p "$DEST/exams" && cd "$DEST" || exit 1

# The file list is DERIVED, not hand-maintained. It used to be four lines of
# literal filenames that a new exam had to be added to by hand, and CI needed
# a dedicated job to catch the times it was not — an exam in the repo but not
# in this list installs as a task list with no seed behind it.
FILES="cka.sh activate.sh VERSION"
for n in $(seq 1 "$COUNT"); do
  FILES="$FILES exams/exam${n}.sh exams/setup${n}.sh"
done

# Fetch everything, but do NOT abort the whole install because one file is
# missing. A single 404 — a partial push, a renamed file, or just CDN lag
# right after a release — used to leave you with a half-populated directory
# and no working exams at all. Missing files are reported; the install only
# fails if the exam you actually asked for is not there.
MISSING=""
for f in $FILES; do
  curl -fsSL "${RAW}/${f}" -o "$f" 2>/dev/null || MISSING="$MISSING $f"
done
chmod +x ./*.sh ./exams/*.sh 2>/dev/null

if [ -n "$MISSING" ]; then
  echo
  echo "  warning: could not download:$MISSING"
  echo "  (everything else installed; those exams will be unavailable)"
fi

# Install only. 'cka use <name>' will seed whichever exam you pick.
case "$EXAM" in
  none|no|skip|0)
    echo
    echo "  Installed. Nothing seeded yet — selecting an exam builds it:"
    echo
    echo "    source ${DEST}/activate.sh"
    echo "    cka              # the dashboard: every exam, and what is seeded"
    echo "    cka use netpol   # select one; it is built if it is not there"
    echo
    exit 0 ;;
esac

# The one thing worth failing over: the exam that was actually requested.
case "$EXAM" in
  ''|*[!0-9]*) echo "  EXAM must be a number 1-${COUNT}, or 'none' — got '$EXAM'"; exit 1 ;;
esac
[ "$EXAM" -ge 1 ] && [ "$EXAM" -le "$COUNT" ] \
  || { echo "  there is no exam ${EXAM} — the range is 1-${COUNT}"; exit 1; }

for f in "exams/setup${EXAM}.sh" "exams/exam${EXAM}.sh"; do
  [ -s "$f" ] || { echo "  cannot start exam ${EXAM}: ${f} is missing"; exit 1; }
done

# Select the exam we are about to seed. Without this, 'cka use' is the only
# thing that ever writes the selection, so a returning user who had selected
# a different exam in an earlier session got THAT exam's tasks from 'q 1' —
# while bootstrap had just seeded this one and told them it was ready.
# Reported from a session that installed exam 1 and was handed exam 7 task 1.
STATE="${CKA_STATE:-${HOME}/.cka-current}"
printf '%s\n' "$EXAM" > "$STATE" 2>/dev/null

exec "./exams/setup${EXAM}.sh"
