#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · scripts/audit-graders.sh
#
#  Looks for graders that FAIL OPEN — that award points when
#  they should not.
#
#  This is the bug this repo keeps producing. Six have been
#  found and fixed so far, and every one had the same shape:
#  a check whose deciding expression is trivially true when
#  kubectl returns nothing. Examples that shipped:
#
#      [ "$(kubectl ...)" != "true" ]     empty != true, so it passed
#                                         with no cluster at all
#      [ "$(...)" = "$(...)" ]            "" = "", so it passed
#      ! kubectl get pod x                absent means correct, and
#                                         everything is absent
#
#  Exams 5, 8 and 9 each handed out free points this way, and
#  one of them scored 22/100 against a cluster that did not
#  exist. So there are two checks here:
#
#    1. BEHAVIOURAL — run every grader with no kubectl on
#       PATH. Every exam must score exactly 0/100. This is the
#       decisive one: it cannot produce a false positive, and
#       it catches shapes no pattern match would.
#
#    2. STATIC — flag any single task whose case arm decides
#       on a negation with no positive gate in front of it.
#
#    ./scripts/audit-graders.sh
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";D="";BO="";N=""; fi

FAIL=0
EXAMS="exam.sh $(ls exam[0-9]*.sh 2>/dev/null | sort -V | tr '\n' ' ')"

# ── 1. behavioural ──────────────────────────────────────────
printf "\n%s  Graders against no cluster%s  %s(every one must score 0/100)%s\n\n" "$BO" "$N" "$D" "$N"

# A directory with nothing in it, prepended to nothing: kubectl, helm and ssh
# all become "command not found". That is a harsher environment than a broken
# cluster and is exactly the point — a grader that scores anything here is
# reading nothing and awarding points for it.
EMPTY="$(mktemp -d)"
HOMEDIR="$(mktemp -d)"
trap 'rm -rf "$EMPTY" "$HOMEDIR"' EXIT

for f in $EXAMS; do
  [ -f "$f" ] || continue
  score="$(env -i PATH="$EMPTY:/usr/bin:/bin" HOME="$HOMEDIR" \
             bash "$f" grade 2>/dev/null \
           | grep -oE 'SCORE: [0-9]+/[0-9]+' | head -1 | sed 's/SCORE: //')"
  case "$score" in
    0/*)  printf "    %s✔%s %-11s %s\n" "$G" "$N" "$f" "$score" ;;
    "")   printf "    %s✘%s %-11s %sno score printed at all%s\n" "$R" "$N" "$f" "$R" "$N"; FAIL=1 ;;
    *)    printf "    %s✘%s %-11s %s%s — points awarded with no cluster%s\n" "$R" "$N" "$f" "$R" "$score" "$N"; FAIL=1 ;;
  esac
done

# ── 2. static ───────────────────────────────────────────────
printf "\n%s  Case arms deciding on a negation with no positive gate%s\n\n" "$BO" "$N"

python3 - "$@" <<'PY'
import re, sys, glob, os

# The functions that prove something POSITIVE was read from the cluster. An
# arm that calls one of these has established the cluster exists before it
# starts reasoning about what is absent from it.
GATES = ("nsok", "nodeexists", "gwapi", "hasns", "relok", "nodefield",
         "pyspec", "pyns", "pycl", "pyjson", "check ", "kubectl get ns",
         "kubectl get node")

NEGATIVE = re.compile(r'!=|\[\s*!\s|\|\|\s*return\s+0|^\s*!\s|-z\s')
POSITIVE = re.compile(r'(?<![!<>])=\s|-n\s|\bgrep -q\b|\btest -f\b|\[\s*-f\s|\[\s*-s\s')

TTY = sys.stdout.isatty()
RED = "\033[31m" if TTY else ""
GRN = "\033[32m" if TTY else ""
OFF = "\033[0m"  if TTY else ""

problems = 0
for path in sorted(glob.glob("exam*.sh"), key=lambda p: (len(p), p)):
    src = open(path, encoding="utf-8").read()
    m = re.search(r'^check\(\)\{(.*?)^\}', src, re.S | re.M)
    if not m:
        continue
    body = m.group(1)
    # Split into 'N)' ... ';;' arms.
    for arm in re.finditer(r'^\s{4}(\d+)\)(.*?);;\s*$', body, re.S | re.M):
        n, text = arm.group(1), arm.group(2)
        code = "\n".join(l for l in text.splitlines()
                         if not l.strip().startswith("#"))
        if not NEGATIVE.search(code):
            continue
        if any(g in code for g in GATES):
            continue
        if POSITIVE.search(code):
            continue
        problems += 1
        print("    %s✘%s %-11s task %-3s decides on a negation and never proves"
              % (RED, OFF, path, n))
        print("      the cluster is there. It would score with kubectl uninstalled.")
        for l in code.strip().splitlines()[:4]:
            print("        %s" % l.strip())

if problems == 0:
    print("    %s✔%s none" % (GRN, OFF))
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] || FAIL=1

printf "\n"
if [ "$FAIL" = "0" ]; then
  printf "  %sno grader fails open%s\n\n" "$G$BO" "$N"; exit 0
fi
printf "  %sat least one grader can award points it should not%s\n\n" "$R$BO" "$N"; exit 1
