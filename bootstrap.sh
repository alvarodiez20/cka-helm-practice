#!/usr/bin/env bash
# Downloads the exams and prepares the environment in one go.
#   curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-helm-practice/main/bootstrap.sh | bash
#
# By default it seeds exam 1. To seed exam 2 or 3 instead:
#   curl -sL .../bootstrap.sh | EXAM=2 bash
#   curl -sL .../bootstrap.sh | EXAM=3 bash
set -uo pipefail

GH_USER="${GH_USER:-alvarodiez20}"
BRANCH="${GH_BRANCH:-main}"
EXAM="${EXAM:-1}"
RAW="https://raw.githubusercontent.com/${GH_USER}/cka-helm-practice/${BRANCH}"
DEST="${HOME}/cka-helm-practice"

echo
echo "  Downloading cka-helm-practice from ${GH_USER}..."
mkdir -p "$DEST" && cd "$DEST" || exit 1

for f in setup.sh exam.sh setup2.sh exam2.sh setup3.sh exam3.sh activate.sh VERSION; do
  curl -fsSL "${RAW}/${f}" -o "$f" \
    || { echo "  could not download ${f} from ${RAW}"; exit 1; }
done
chmod +x setup.sh exam.sh setup2.sh exam2.sh setup3.sh exam3.sh activate.sh

case "$EXAM" in
  2) exec ./setup2.sh ;;
  3) exec ./setup3.sh ;;
  *) exec ./setup.sh ;;
esac
