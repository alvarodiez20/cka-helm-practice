#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · scripts/check-tasks.sh
#
#  Renders every task of every exam and insists it comes out
#  whole.
#
#  This exists because 'bash -n' is not enough. An unescaped
#  double quote inside one of the Q/SOL/WALK strings closes it
#  early; the remainder of the paragraph is then parsed as
#  shell commands, and if it happens to parse — English often
#  does — the script is syntactically valid and quietly broken.
#  That shipped once: a stray pair of quotes in exam7's
#  WALK[1] turned the rest of the paragraph into
#
#      volumes: command not found
#      `WALK[1]': not a valid identifier
#
#  printed in the middle of a candidate's walkthrough.
#
#  So: for all thirteen tasks of all ten exams, run q, solve
#  and explain, and require exit 0, no stderr, and output that
#  is actually there.
#
#    ./scripts/check-tasks.sh
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";D="";BO="";N=""; fi

EXAMS="exam.sh $(ls exam[0-9]*.sh 2>/dev/null | sort -V | tr '\n' ' ')"
HOMEDIR="$(mktemp -d)"
ERR="$(mktemp)"
trap 'rm -rf "$HOMEDIR" "$ERR"' EXIT

FAIL=0
printf "\n%s  Every task renders%s  %s(q · solve · explain, all tasks, all exams)%s\n\n" \
  "$BO" "$N" "$D" "$N"

for f in $EXAMS; do
  [ -f "$f" ] || continue
  total="$(sed -n 's/^TOTAL=\([0-9]*\).*/\1/p' "$f" | head -1)"
  total="${total:-13}"
  bad=""
  for i in $(seq 1 "$total"); do
    for verb in q solve explain; do
      : > "$ERR"
      out="$(HOME="$HOMEDIR" bash "$f" "$verb" "$i" 2>"$ERR")"
      rc=$?
      if [ "$rc" != "0" ]; then
        bad="$bad ${verb}${i}(exit $rc)"
      elif [ -s "$ERR" ]; then
        # Anything on stderr means the string broke apart and the shell tried
        # to run the prose. This is the check that matters.
        bad="$bad ${verb}${i}(stderr)"
        printf "    %s%s%s\n" "$D" "$(head -1 "$ERR" | cut -c1-100)" "$N"
      elif [ "$(printf '%s' "$out" | wc -c)" -lt 40 ]; then
        # An unset array element expands to nothing and prints a bare frame.
        bad="$bad ${verb}${i}(empty)"
      fi
    done
  done
  if [ -z "$bad" ]; then
    printf "    %s✔%s %-11s %s tasks × 3\n" "$G" "$N" "$f" "$total"
  else
    printf "    %s✘%s %-11s%s\n" "$R" "$N" "$f" "$bad"
    FAIL=1
  fi
done

# ── static: where does each task string actually END? ───────
# Rendering catches an ODD number of stray quotes, which breaks the shell
# loudly. It does not catch a BALANCED pair: '"damage"' closes the string and
# reopens it, so the text still assigns — minus the quote characters, and with
# anything in between now subject to expansion. A $( or a backtick in there
# would run.
#
# Every one of these assignments ends with a quote at the end of a line,
# followed by a new assignment. So: find the first unescaped quote after the
# opening one, and complain if it is not where the string is supposed to end.
printf "%s  Task strings close where they should%s\n\n" "$BO" "$N"
python3 - <<'PY'
import re, sys, glob

TTY = sys.stdout.isatty()
RED = "\033[31m" if TTY else ""
GRN = "\033[32m" if TTY else ""
OFF = "\033[0m"  if TTY else ""

NEXT_OK = re.compile(r'^\s*$|^(Q|PTS|SOL|WALK)\[|^#|^[A-Za-z_]+\(\)|^\w+=')
problems = 0

for path in sorted(glob.glob("exam*.sh"), key=lambda p: (len(p), p)):
    src = open(path, encoding="utf-8").read()
    lines = src.splitlines()
    for m in re.finditer(r'^(Q|SOL|WALK)\[(\d+)\]="', src, re.M):
        i = m.end() - 1                      # the opening quote
        j = i + 1
        while j < len(src):
            if src[j] == '"' and src[j-1] != '\\':
                break
            j += 1
        if j >= len(src):
            continue
        # Is the closing quote the last character of its line?
        eol = src.find("\n", j)
        tail = src[j+1:eol if eol != -1 else len(src)]
        nxt  = src[eol+1:src.find("\n", eol+1)] if eol != -1 else ""
        if tail.strip() == "" and NEXT_OK.match(nxt):
            continue
        line_no = src[:j].count("\n") + 1
        problems += 1
        print("    %s✘%s %-11s %s[%s] closes early at line %d"
              % (RED, OFF, path, m.group(1), m.group(2), line_no))
        print("      %s" % lines[line_no-1].strip()[:88])
        print("      an unescaped \" here ends the string; escape it as \\\" or reword")

if problems == 0:
    print("    %s✔%s none" % (GRN, OFF))
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] || FAIL=1

printf "\n"
if [ "$FAIL" = "0" ]; then
  printf "  %severy task renders cleanly%s\n\n" "$G$BO" "$N"; exit 0
fi
printf "  %sat least one task is malformed — usually an unescaped \" in Q/SOL/WALK%s\n\n" "$R$BO" "$N"
exit 1
