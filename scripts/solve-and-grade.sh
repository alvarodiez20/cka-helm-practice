#!/usr/bin/env bash
# ============================================================
#  cka-practice · scripts/solve-and-grade.sh
#
#  Seeds an exam, solves it, and requires 100/100.
#
#      ./scripts/solve-and-grade.sh 11
#      ./scripts/solve-and-grade.sh 1 2 7 9 11
#      ./scripts/solve-and-grade.sh --list
#
#  THIS IS THE CHECK THAT WAS MISSING. scripts/audit-graders.sh
#  proves the NEGATIVE case — that nothing scores against no
#  cluster. Nothing proved the POSITIVE case: that a correct
#  answer scores. So a grader could have been unsatisfiable and
#  every static check in this repo would still have been green.
#
#  It needs a real cluster and it changes it. Run it on
#  something disposable — a kind cluster, a Killercoda
#  playground — never on anything you would miss.
#
#  How an exam is solved, in order of preference:
#
#    1. tests/solutions/N.sh, if it exists. Needed where the
#       walkthrough asks you to EDIT a file rather than run a
#       command, so 'solve N' is instructions rather than a
#       script. Exam 11 is the case in point.
#
#    2. Otherwise, 'exam N solve i' piped to bash, task by
#       task, which is exactly the promise 'solve' makes: the
#       commands, and nothing else.
#
#  Either way the exam grades itself afterwards and anything
#  short of 100/100 is a failure — of the solution, of the
#  grader, or of the seed. All three are bugs.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";D="";BO="";N=""; fi
ok(){   printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
bad(){  printf "  ${R}✘${N} %s\n" "$*"; }

# Exams 5, 6 and 10 break a node, the scheduler or the CNI, and their tasks
# are answered by editing files over ssh on a second machine. They are not
# runnable unattended and are excluded unless named explicitly.
DESTRUCTIVE="5 6 10"
# Exams needing something a plain single-node kind cluster does not have.
NEEDS="8:a control plane with etcdctl and kubeadm
3:internet access to the real chart repositories
5:two nodes and passwordless ssh; it stops a worker's kubelet
6:a cluster you can lose; it takes kube-scheduler down
10:two nodes, passwordless ssh, and internet; it disables a worker's CNI"

usage(){ sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  ""|-h|--help) usage; exit 0 ;;
  --list)
    printf "\n%s  Exams, and whether this can run them unattended%s\n\n" "$BO" "$N"
    while IFS='|' read -r n name _ _ _ topic _; do
      case "$n" in ''|*[!0-9]*) continue ;; esac
      note="$(printf '%s\n' "$NEEDS" | sed -n "s/^${n}://p")"
      case " $DESTRUCTIVE " in
        *" $n "*) printf "  %2s %-12s %sdestructive — %s%s\n" "$n" "$name" "$R" "$note" "$N" ;;
        *) if [ -n "$note" ]; then printf "  %2s %-12s %sneeds %s%s\n" "$n" "$name" "$Y" "$note" "$N"
           else printf "  %2s %-12s %sok%s  %s%s%s\n" "$n" "$name" "$G" "$N" "$D" "$topic" "$N"; fi ;;
      esac
    done < <(sed -n '/^EXAMS="/,/"$/p' cka.sh | sed 's/^EXAMS="//; s/"$//')
    printf "\n"; exit 0 ;;
esac

command -v kubectl >/dev/null || { bad "no kubectl"; exit 1; }
kubectl get nodes >/dev/null 2>&1 || { bad "kubectl cannot reach a cluster — this check needs one"; exit 1; }

FAIL=0
for n in "$@"; do
  case "$n" in ''|*[!0-9]*) bad "not an exam number: $n"; FAIL=1; continue ;; esac
  exam="exams/exam${n}.sh"; seed="exams/setup${n}.sh"
  [ -f "$exam" ] && [ -f "$seed" ] || { bad "exam $n is not in this repo"; FAIL=1; continue; }

  printf "\n%s  ── exam %s ──%s\n\n" "$BO" "$n" "$N"

  if ! bash "$seed" >/tmp/seed.$n.log 2>&1; then
    bad "the seed failed — last lines:"; tail -5 /tmp/seed.$n.log | sed 's/^/      /'
    FAIL=1; continue
  fi
  ok "seeded"

  # A seeded exam must score 0 before anything is solved. If it does not, a
  # grader is passing on the seed's own state, which means the task asks for
  # something that is already true.
  pre="$(bash "$exam" grade 2>/dev/null | grep -oE 'SCORE: [0-9]+/[0-9]+' | head -1)"
  case "${pre#SCORE: }" in
    0/*) ok "scores 0/100 before solving" ;;
    *)   warn "scores ${pre#SCORE: } before anything is solved — a task may already be satisfied by the seed" ;;
  esac

  if [ -x "tests/solutions/${n}.sh" ]; then
    ok "using tests/solutions/${n}.sh"
    bash "tests/solutions/${n}.sh" >/tmp/solve.$n.log 2>&1 || warn "the solution script exited non-zero"
  else
    ok "using each task's own 'solve' output"
    total="$(sed -n 's/^TOTAL=\([0-9]*\).*/\1/p' "$exam" | head -1)"; total="${total:-13}"
    : > /tmp/solve.$n.log
    for i in $(seq 1 "$total"); do
      # 'solve' prints a heading, the commands, then a footer pointing at
      # 'explain'. Only the middle is meant to run.
      bash "$exam" solve "$i" 2>/dev/null \
        | sed -n '/Solution to task/,/want the reasoning/p' \
        | sed '1d; $d' \
        | bash >>/tmp/solve.$n.log 2>&1
    done
  fi

  post="$(bash "$exam" grade 2>/dev/null | grep -oE 'SCORE: [0-9]+/[0-9]+' | head -1)"
  post="${post#SCORE: }"
  if [ "$post" = "100/100" ]; then
    ok "${G}${BO}100/100${N} after solving"
  else
    bad "scores ${post:-nothing} after solving its own solutions"
    printf "      %sthe tasks that did not pass:%s\n" "$D" "$N"
    bash "$exam" grade 2>/dev/null | grep '✘' | sed 's/^/      /'
    printf "      %ssolve log: /tmp/solve.%s.log%s\n" "$D" "$n" "$N"
    FAIL=1
  fi
done

printf "\n"
if [ "$FAIL" = "0" ]; then printf "  %severy exam scored 100/100 from its own solutions%s\n\n" "$G$BO" "$N"; exit 0; fi
printf "  %sat least one exam cannot be solved by its own solutions%s\n\n" "$R$BO" "$N"; exit 1
