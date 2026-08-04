#!/usr/bin/env bash
# ============================================================
#  cka-practice · cka.sh
#  One entry point for all eleven exams.
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
EXAMDIR="$HERE/exams"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"
STATE="${CKA_STATE:-$HOME/.cka-current}"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

# Kept as a flat pipe-separated list so it works on bash 3.2, which has no
# associative arrays and is what macOS still ships.
#
#   number | name | exam script | setup script | marker namespaces | topic | domain
#
# The MARKER NAMESPACES are what "is this exam seeded?" is decided on: the
# namespaces its own seed creates, which nothing else in the cluster owns.
#
# The DOMAIN is the CKA curriculum domain the exam belongs to. Exam numbers are
# historical — they are the order the exams were written in, and they are load
# bearing (answer directories, the numbered commands, everyone's muscle memory),
# so they do not move. The dashboard and the docs group by DOMAIN instead, which
# is the order you would actually revise in. See domain_order below.
EXAMS="\
1|helm-core|exam1.sh|setup1.sh|apps hidden-77|Helm: install, rollback, values, packaging|arch
2|helm-values|exam2.sh|setup2.sh|stage broken-77|Helm: repos, values files, --atomic, subcharts|arch
3|helm-oci|exam3.sh|setup3.sh|limbo|Helm: real charts, CRDs, OCI registries|arch
4|netpol|exam4.sh|setup4.sh|frontend backend monitoring shop netdebug|NetworkPolicy and network troubleshooting|net
5|nodes|exam5.sh|setup5.sh|node-lab|Worker node failures: kubelet, taints, static pods|tshoot
6|tshoot|exam6.sh|setup6.sh|tshoot|General troubleshooting: control plane, pods, RBAC|tshoot
7|storage|exam7.sh|setup7.sh|store-lab|Storage: PV, PVC, StorageClass, StatefulSet volumes|store
8|cluster|exam8.sh|setup8.sh|drain-lab|etcd backup and restore, kubeadm, certificates|arch
9|workloads|exam9.sh|setup9.sh|work-lab|Workloads and scheduling: rollouts, Jobs, affinity|work
10|gateway|exam10.sh|setup10.sh|edge-lab|Ingress, Gateway API, and CNI troubleshooting|net
11|kustomize|exam11.sh|setup11.sh|kust-lab|Kustomize: overlays, patches, generators, apply -k|arch"

# The five CKA domains, in the order the dashboard shows them: heaviest first,
# which is also a defensible revision order. key|weight|label
DOMAINS="\
tshoot|30%|Troubleshooting
arch|25%|Cluster architecture, installation and configuration
net|20%|Services and networking
work|15%|Workloads and scheduling
store|10%|Storage"

# Exams 5, 6 and 10 break the cluster on purpose, so they are never seeded
# without being asked for. Everything else is safe to build unattended.
#   5   stops and misconfigures the kubelet on a worker
#   6   breaks the scheduler
#   10  disables the CNI configuration on a worker
DESTRUCTIVE="5 6 10"

field(){ printf '%s\n' "$EXAMS" | awk -F'|' -v k="$1" -v c="$2" '$1==k||$2==k{print $c; exit}'; }
num_of(){ field "$1" 1; }
name_of(){ field "$1" 2; }
script_of(){ field "$1" 3; }
setup_of(){ field "$1" 4; }
marker_of(){ field "$1" 5; }
topic_of(){ field "$1" 6; }
domain_of(){ field "$1" 7; }
known(){ [ -n "$(num_of "$1")" ]; }

# The exam numbers, grouped by domain and ordered heaviest domain first. This
# is the order everything user-facing iterates in.
domain_order(){
  local key
  printf '%s\n' "$DOMAINS" | while IFS='|' read -r key _ _; do
    printf '%s\n' "$EXAMS" | awk -F'|' -v d="$key" '$7==d{print $1}'
  done
}
destructive(){ case " $DESTRUCTIVE " in *" $(num_of "$1") "*) return 0 ;; *) return 1 ;; esac; }

# ── is an exam actually present in the cluster? ─────────────
# Selecting an exam used to print its task list without ever looking at the
# cluster, so 'cka use netpol' after a bootstrap that only seeded exam 1 gave
# you thirteen tasks and nothing to solve them against. One 'kubectl get ns'
# per process answers it for all of them.
ALL_NS=""
ns_snapshot(){
  [ -n "$ALL_NS" ] && return 0
  ALL_NS="$(kubectl get ns --no-headers 2>/dev/null | awk '$2=="Active"{print $1}')"
  ALL_NS="${ALL_NS:-__no_cluster__}"
}

seeded(){ # every marker namespace of this exam exists and is Active
  local ns markers
  markers="$(marker_of "$1")"
  [ -n "$markers" ] || return 1
  ns_snapshot
  for ns in $markers; do
    printf '%s\n' "$ALL_NS" | grep -qx "$ns" || return 1
  done
  return 0
}

current(){ # the selected exam number, defaulting to 1
  local c=""
  [ -f "$STATE" ] && c="$(tr -d '[:space:]' < "$STATE" 2>/dev/null)"
  [ -n "$c" ] && known "$c" && num_of "$c" || echo 1
}

run(){ # run <exam> <args...>
  local n; n="$(num_of "$1")"; shift
  local s; s="$(script_of "$n")"
  [ -n "$s" ] && [ -f "$EXAMDIR/$s" ] || { printf "\n  %sexam %s is not installed%s\n\n" "$R" "$n" "$N" >&2; return 1; }
  # Invoked through bash rather than executed directly, so a script that has
  # lost its executable bit (an editor, a careless sed -i) still runs.
  EXAM_HOME="${EXAM_HOME:-$HERE}" bash "$EXAMDIR/$s" "$@"
}

score_of(){ # prints "got/max", or "-" if the exam cannot be graded here
  local out; out="$(run "$1" grade 2>/dev/null | grep -oE 'SCORE: [0-9]+/[0-9]+' | head -1)"
  [ -n "$out" ] && printf '%s' "${out#SCORE: }" || printf '%s' "-"
}

# ── the dashboard ───────────────────────────────────────────
# Grouped by CKA domain, heaviest domain first, because the exam NUMBERS are
# just the order these were written in and reading them top to bottom told you
# nothing about what to revise. The numbers are still shown and still work.
score_cell(){ # score_cell <exam> <"scores"|"">
  # An unseeded exam has no score to report and grading it would only waste a
  # few seconds arriving at 0, so say so and skip the grader entirely.
  if ! seeded "$1"; then printf '%s' "${D}not seeded${N}"; return; fi
  if [ "${2:-}" != "scores" ]; then printf '%s' "$D·$N"; return; fi
  local sc got; sc="$(score_of "$1")"
  case "$sc" in
    -)   printf '%s' "${D}not seeded${N}" ;;
    0/*) printf '%s' "${D}${sc}${N}" ;;
    *)   got="${sc%%/*}"
         if [ "${got:-0}" -ge 66 ]; then printf '%s' "${G}${sc}${N}"
         else printf '%s' "${Y}${sc}${N}"; fi ;;
  esac
}

dashboard(){ # $1 = "scores" to grade every exam (slow)
  local cur dkey dweight dlabel n mark
  cur="$(current)"
  printf "\n%s  cka-practice%s %sv%s%s — %s exams, 100 points each, pass mark 66\n" \
    "$BO" "$N" "$D" "$VERSION" "$N" "$(printf '%s\n' "$EXAMS" | wc -l | tr -d ' ')"
  printf "  %sgrouped by CKA domain, heaviest first%s\n" "$D" "$N"

  printf '%s\n' "$DOMAINS" | while IFS='|' read -r dkey dweight dlabel; do
    printf "\n  %s%s  %s%s\n" "$BO" "$dweight" "$dlabel" "$N"
    printf '%s\n' "$EXAMS" | awk -F'|' -v d="$dkey" '$7==d' \
      | while IFS='|' read -r n name script setup marker topic domain; do
          mark="  "; [ "$n" = "$cur" ] && mark="${G}▸ ${N}"
          # %2s, not %-4s: right-aligned so 1 and 11 share a column edge, and
          # the topic column is 52 wide because the longest one is 51.
          printf "  %s%2s  %-13s %-52s %s\n" \
            "$mark" "$n" "$name" "$topic" "$(score_cell "$n" "${1:-}")"
        done
  done

  printf "\n  %sselected:%s %s%s%s  %s(%s)%s\n" "$D" "$N" "$BO" "$(name_of "$cur")" "$N" \
    "$D" "$(topic_of "$cur")" "$N"
  if [ "${1:-}" != "scores" ]; then
    printf "  %scka scores%s grades every exam — takes a couple of minutes.\n" "$D" "$N"
  fi
  printf "\n  %scka use <name>%s   switch     %sq N · grade · explain N · next%s\n\n" \
    "$BO" "$N" "$BO" "$N"
}

usage(){
  printf "\n%s  cka%s — one entry point for every exam\n\n" "$BO" "$N"
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
  printf "%s  THE NAMES%s  %s(by CKA domain — the number is just the order they were written)%s\n" \
    "$BO" "$N" "$D" "$N"
  printf '%s\n' "$DOMAINS" | while IFS='|' read -r dkey dweight dlabel; do
    printf "\n    %s%s %s%s\n" "$D" "$dweight" "$dlabel" "$N"
    printf '%s\n' "$EXAMS" | awk -F'|' -v d="$dkey" '$7==d' \
      | while IFS='|' read -r n name script setup marker topic domain; do
          printf "    %2s  %-13s %s\n" "$n" "$name" "$topic"
        done
  done
  printf "\n  %sThe old numbered commands (q6 4, grade7, exam3) still work.%s\n\n" "$D" "$N"
}

# ── is the exam you are about to work on actually there? ────
# Showing a task list for an exam that does not exist in the cluster is how a
# stale selection presents: the tasks read fine, nothing they refer to is
# there, and the exam looks broken rather than unbuilt. Say it once, before
# the output, and name the command that fixes it.
warn_unseeded(){ # $1 = exam number or name
  local n name
  n="$(num_of "$1")"; [ -n "$n" ] || return 0
  seeded "$n" && return 0
  name="$(name_of "$n")"
  if [ "$ALL_NS" = "__no_cluster__" ]; then
    printf "\n  %s! no cluster reachable — nothing here can be graded%s\n" "$Y" "$N" >&2
  else
    printf "\n  %s! '%s' is not seeded in this cluster%s — the objects these tasks\n" "$Y" "$name" "$N" >&2
    printf "    refer to do not exist yet.\n" >&2
    printf "  %sbuild it:  cka use %s      see what is:  cka%s\n" "$D" "$name" "$N" >&2
  fi
}

# ── the first unsolved task ─────────────────────────────────
next_task(){
  local n; n="$(num_of "${1:-$(current)}")"
  warn_unseeded "$n"
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
    # bootstrap.sh seeds ONE exam. Selecting any other one used to hand you a
    # task list with nothing behind it in the cluster, which reads as a broken
    # exam rather than an unseeded one. So build it here.
    if ! seeded "$n"; then
      seed="$(setup_of "$n")"
      if [ "$ALL_NS" = "__no_cluster__" ]; then
        printf "  %sno cluster reachable — cannot seed '%s'. The tasks below are%s\n" "$R" "$(name_of "$n")" "$N" >&2
        printf "  %sstill readable; 'reset' will build it once kubectl works.%s\n\n" "$D" "$N" >&2
      elif [ ! -f "$EXAMDIR/$seed" ]; then
        printf "  %s'%s' is not seeded and %s is missing%s\n\n" "$R" "$(name_of "$n")" "$seed" "$N" >&2
      elif destructive "$n" && [ -t 0 ]; then
        # These break a node or the scheduler. Never without being asked.
        printf "  %s'%s' is not seeded, and its seed BREAKS THE CLUSTER on purpose%s\n" \
          "$Y" "$(name_of "$n")" "$N"
        printf "  %s(exam5restore / exam6restore undo it).%s\n" "$D" "$N"
        printf "  seed it now? [y/N] "
        read -r reply
        case "$reply" in
          [yY]*) EXAM_HOME="$HERE" bash "$EXAMDIR/$seed" ;;
          *) printf "\n  %sleft alone — run 'reset' when you want it%s\n\n" "$D" "$N"; exit 0 ;;
        esac
      elif destructive "$n"; then
        printf "  %s'%s' is not seeded. Its seed breaks the cluster on purpose, so it%s\n" "$Y" "$(name_of "$n")" "$N"
        printf "  %swill not run unattended — use 'reset' to build it.%s\n\n" "$D" "$N"
        exit 0
      else
        printf "  %s'%s' is not seeded yet — building it now%s\n" "$D" "$(name_of "$n")" "$N"
        EXAM_HOME="$HERE" bash "$EXAMDIR/$seed" \
          || { printf "\n  %sseeding failed — fix the above and run 'reset'%s\n\n" "$R" "$N" >&2; exit 1; }
      fi
    fi
    run "$n" list ;;
  next)    next_task "${2:-}" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-practice %s\n" "$VERSION" ;;
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
      # A warning first for the verbs that read the cluster or describe what is
      # in it. Not for 'reset', which is the fix, nor for 'help'/'version'.
      list|q|show|grade|explain|walk|steps|solve)
                  warn_unseeded "$target"; run "$target" "$cmd" "$@" ;;
      reset|help|version) run "$target" "$cmd" "$@" ;;
      next)       next_task "$target" ;;
      examhelp)   run "$target" help ;;
      # Each exam names its dashboard differently; 'info' is the alias that
      # works everywhere, so you do not have to remember which is which.
      info)       run "$target" info ;;
      *) printf "\n  %sunknown command: %s%s\n" "$R" "$cmd" "$N" >&2; usage >&2; exit 1 ;;
    esac ;;
esac
