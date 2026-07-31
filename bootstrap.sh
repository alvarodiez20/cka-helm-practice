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

for f in setup.sh exam.sh setup2.sh exam2.sh setup3.sh exam3.sh \
         setup4.sh exam4.sh setup5.sh exam5.sh \
         setup6.sh exam6.sh setup7.sh exam7.sh \
         setup8.sh exam8.sh setup9.sh exam9.sh \
         cka.sh activate.sh VERSION; do
  curl -fsSL "${RAW}/${f}" -o "$f" \
    || { echo "  could not download ${f} from ${RAW}"; exit 1; }
done
chmod +x setup.sh exam.sh setup2.sh exam2.sh setup3.sh exam3.sh \
         setup4.sh exam4.sh setup5.sh exam5.sh setup6.sh exam6.sh \
         setup7.sh exam7.sh setup8.sh exam8.sh setup9.sh exam9.sh \
         cka.sh activate.sh

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
