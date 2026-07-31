#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · cka.sh
#  One entry point for all nine exams.
#
#  The old interface needed the exam number baked into every
#  command name — 'q6 6' meaning task 6 of exam 6, out of 72
#  shell functions. This replaces that with a SELECTED exam and
#  one set of unnumbered verbs:
#
#      cka                  the dashboard
#      cka use storage      select an exam, by name or number
#      q 3                  show task 3 of the selected exam
#      grade                grade the selected exam
#      next                 jump to the first unsolved task
#
#  The numbered functions still work, so nothing breaks
#  mid-session.
# ============================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"
STATE="${CKA_STATE:-$HOME/.cka-current}"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

# number | name | script | one-line topic
# Kept as a flat list so it works on bash 3.2 (no associative arrays).
EXAMS="\
1|helm-core|exam.sh|Helm: install, rollback, values, packaging
2|helm-values|exam2.sh|Helm: repos, values files, --atomic, subcharts
3|helm-oci|exam3.sh|Helm: real charts, CRDs, OCI registries
4|netpol|exam4.sh|NetworkPolicy and network troubleshooting
5|nodes|exam5.sh|Worker node failures: kubelet, taints, static pods
6|tshoot|exam6.sh|General troubleshooting: control plane, pods, RBAC
7|storage|exam7.sh|Storage: PV, PVC, StorageClass, StatefulSet volumes
8|cluster|exam8.sh|etcd backup and restore, kubeadm, certificates
9|workloads|exam9.sh|Workloads and scheduling: rollouts, Jobs, affinity"

field(){ printf '%s\n' "$EXAMS" | awk -F'|' -v k="$1" -v c="$2" '$1==k||$2==k{print $c; exit}'; }
num_of(){ field "$1" 1; }
name_of(){ field "$1" 2; }
script_of(){ field "$1" 3; }
topic_of(){ field "$1" 4; }
known(){ [ -n "$(num_of "$1")" ]; }

current(){ # the selected exam number, defaulting to 1
  local c=""
  [ -f "$STATE" ] && c="$(tr -d '[:space:]' < "$STATE" 2>/dev/null)"
  [ -n "$c" ] && known "$c" && num_of "$c" || echo 1
}

run(){ # run <exam> <args...>
  local n; n="$(num_of "$1")"; shift
  local s; s="$(script_of "$n")"
  [ -n "$s" ] && [ -f "$HERE/$s" ] || { printf "\n  %sexam %s is not installed%s\n\n" "$R" "$n" "$N" >&2; return 1; }
  # Invoked through bash rather than executed directly, so a script that has
  # lost its executable bit (an editor, a careless sed -i) still runs.
  EXAM_HOME="${EXAM_HOME:-$HERE}" bash "$HERE/$s" "$@"
}

score_of(){ # prints "got/max", or "-" if the exam cannot be graded here
  local out; out="$(run "$1" grade 2>/dev/null | grep -oE 'SCORE: [0-9]+/[0-9]+' | head -1)"
  [ -n "$out" ] && printf '%s' "${out#SCORE: }" || printf '%s' "-"
}

# ── the dashboard ───────────────────────────────────────────
dashboard(){ # $1 = "scores" to grade every exam (slow)
  local cur; cur="$(current)"
  printf "\n%s  cka-helm-practice%s %sv%s%s — nine exams, 100 points each, pass mark 66\n\n" \
    "$BO" "$N" "$D" "$VERSION" "$N"
  printf "  %s  %-4s %-13s %-52s %s%s\n" "$D" "" "NAME" "TOPIC" "SCORE" "$N"
  printf '%s\n' "$EXAMS" | while IFS='|' read -r n name script topic; do
    local mark="  "; [ "$n" = "$cur" ] && mark="${G}▸ ${N}"
    local sc="$D·$N"
    if [ "${1:-}" = "scores" ]; then
      sc="$(score_of "$n")"
      case "$sc" in
        -) sc="${D}not seeded${N}" ;;
        0/*) sc="${D}${sc}${N}" ;;
        *) local got="${sc%%/*}"
           if [ "${got:-0}" -ge 66 ]; then sc="${G}${sc}${N}"; else sc="${Y}${sc}${N}"; fi ;;
      esac
    fi
    printf "  %s%-4s %-13s %-52s %s\n" "$mark" "$n" "$name" "$topic" "$sc"
  done
  printf "\n  %sselected:%s %s%s%s  %s(%s)%s\n" "$D" "$N" "$BO" "$(name_of "$cur")" "$N" \
    "$D" "$(topic_of "$cur")" "$N"
  if [ "${1:-}" != "scores" ]; then
    printf "  %scka scores%s grades all nine — takes a minute.\n" "$D" "$N"
  fi
  printf "\n  %scka use <name>%s   switch     %sq N · grade · explain N · next%s\n\n" \
    "$BO" "$N" "$BO" "$N"
}

usage(){
  printf "\n%s  cka%s — one entry point for all nine exams\n\n" "$BO" "$N"
  printf "%s  PICK AN EXAM%s\n\n" "$BO" "$N"
  printf "    %-24s %s\n" "cka" "the dashboard: every exam, and which is selected"
  printf "    %-24s %s\n" "cka scores" "the same, plus your score in each (slow)"
  printf "    %-24s %s\n" "cka use storage" "select an exam by name"
  printf "    %-24s %s\n\n" "cka use 7" "or by number — the same thing"
  printf "%s  THEN, ON THE SELECTED EXAM%s\n\n" "$BO" "$N"
  printf "    %-24s %s\n" "cka" "(after 'use') ... or just:"
  printf "    %-24s %s\n" "list" "every task, with points and ✔/✘"
  printf "    %-24s %s\n" "q 3" "show task 3"
  printf "    %-24s %s\n" "next" "jump to the first unsolved task"
  printf "    %-24s %s\n" "grade" "grade everything"
  printf "    %-24s %s\n" "grade 3" "grade one task"
  printf "    %-24s %s\n" "explain 3" "the walkthrough, with reasoning"
  printf "    %-24s %s\n" "solve 3" "just the commands"
  printf "    %-24s %s\n" "info" "that exam's own dashboard, whatever it is"
  printf "    %-24s %s\n" "reset" "re-seed it"
  printf "    %-24s %s\n\n" "examhelp" "the selected exam's full help"
  printf "%s  ANY EXAM, WITHOUT SELECTING IT%s\n\n" "$BO" "$N"
  printf "    %-24s %s\n" "cka storage q 3" "task 3 of the storage exam"
  printf "    %-24s %s\n\n" "cka 7 grade" "the same, by number"
  printf "%s  THE NAMES%s\n\n" "$BO" "$N"
  printf '%s\n' "$EXAMS" | while IFS='|' read -r n name script topic; do
    printf "    %-3s %-13s %s\n" "$n" "$name" "$topic"
  done
  printf "\n  %sThe old numbered commands (q6 4, grade7, exam3) still work.%s\n\n" "$D" "$N"
}

# ── the first unsolved task ─────────────────────────────────
next_task(){
  local n; n="$(num_of "${1:-$(current)}")"
  local i found=""
  for i in $(seq 1 13); do
    if ! run "$n" grade "$i" 2>/dev/null | grep -q '✔'; then found="$i"; break; fi
  done
  if [ -z "$found" ]; then
    printf "\n  %s✔ every task in '%s' is solved.%s  %scka use <next exam>%s\n\n" \
      "$G" "$(name_of "$n")" "$N" "$D" "$N"
    return 0
  fi
  printf "\n  %snext unsolved in '%s': task %s%s\n" "$D" "$(name_of "$n")" "$found" "$N"
  run "$n" q "$found"
}

# ── dispatch ────────────────────────────────────────────────
case "${1:-dashboard}" in
  dashboard|"") dashboard ;;
  scores)       dashboard scores ;;
  use|select|switch)
    if [ -z "${2:-}" ]; then
      printf "\n  %swhich one?%s  e.g.  cka use storage\n\n" "$R" "$N" >&2; exit 1
    fi
    if ! known "$2"; then
      printf "\n  %sno exam called '%s'%s. The names are:\n\n" "$R" "$2" "$N" >&2
      printf '%s\n' "$EXAMS" | awk -F'|' '{printf "    %-3s %s\n",$1,$2}' >&2
      printf "\n" >&2; exit 1
    fi
    num_of "$2" > "$STATE"
    n="$(num_of "$2")"
    printf "\n  %sselected%s %s%s%s — %s\n" "$D" "$N" "$BO" "$(name_of "$n")" "$N" "$(topic_of "$n")"
    printf "  %sq N · grade · explain N · next%s\n\n" "$D" "$N"
    run "$n" list ;;
  next)    next_task "${2:-}" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s\n" "$VERSION" ;;
  *)
    # 'cka <exam> <cmd> ...' addresses one exam directly;
    # 'cka <cmd> ...' acts on the selected one.
    if known "$1"; then
      target="$1"; shift
      [ $# -eq 0 ] && set -- list
    else
      target="$(current)"
    fi
    cmd="$1"; shift
    case "$cmd" in
      list|q|show|grade|explain|walk|steps|solve|reset|help|version) run "$target" "$cmd" "$@" ;;
      next)       next_task "$target" ;;
      examhelp)   run "$target" help ;;
      # Each exam names its dashboard differently; 'info' is the alias that
      # works everywhere, so you do not have to remember which is which.
      info)       run "$target" info ;;
      *) printf "\n  %sunknown command: %s%s\n" "$R" "$cmd" "$N" >&2; usage >&2; exit 1 ;;
    esac ;;
esac
