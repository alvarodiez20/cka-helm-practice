#!/usr/bin/env bash
# ============================================================
#  cka-practice · activate.sh
#  Defines the exam commands in YOUR shell, so you never have
#  to type ./exams/exam7.sh or sit in the repo directory.
#
#    source ~/cka-practice/activate.sh
#
#  THE SHORT VERSION
#
#    cka                  the dashboard — every exam, and which is selected
#    cka use storage      select an exam by name (or number)
#    q 3 · grade · explain 3 · next · info
#
#  The verbs are unnumbered and act on the SELECTED exam, so you never
#  have to encode the exam into the command name.
#
#  Names:  helm-core helm-values helm-oci netpol nodes tshoot
#          storage cluster workloads gateway kustomize
#
#  The old numbered commands (exam6, q6 4, grade7, explain3 2) still
#  work and are defined below, so nothing breaks mid-session.
#
# ============================================================

# This file must be sourced, not executed: if you run it, the functions
# are defined in a subshell that dies on exit.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "  this has to be loaded into your current shell:" >&2
  echo "      source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

EXAM_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export EXAM_HOME
CKA_EXAMS="$EXAM_HOME/exams"
export CKA_EXAMS

# How many exams there are, read from the dispatcher rather than hard-coded
# here — adding an exam should mean editing cka.sh and nothing else.
CKA_COUNT="$(grep -cE '^[0-9]+\|[a-z-]+\|exam' "$EXAM_HOME/cka.sh" 2>/dev/null)"
[ "${CKA_COUNT:-0}" -ge 1 ] 2>/dev/null || CKA_COUNT=11

# ── the dispatcher, and the unnumbered verbs ────────────────
# These act on whichever exam 'cka use' selected. With nothing selected the
# default is exam 1, which is exactly what these commands did before — so
# 'q 4' still means what it always meant.
cka()        { "$EXAM_HOME/cka.sh" "$@"; }
q()          { "$EXAM_HOME/cka.sh" q "$@"; }
grade()      { "$EXAM_HOME/cka.sh" grade "$@"; }
solve()      { "$EXAM_HOME/cka.sh" solve "$@"; }
explain()    { "$EXAM_HOME/cka.sh" explain "$@"; }
next()       { "$EXAM_HOME/cka.sh" next "$@"; }
info()       { "$EXAM_HOME/cka.sh" info; }
list()       { "$EXAM_HOME/cka.sh" list; }
reset()      { "$EXAM_HOME/cka.sh" reset; }

# ── the original per-exam commands, unchanged ───────────────
# examN, qN, gradeN, solveN, explainN, examNhelp, examNreset for every exam.
#
# These used to be 77 hand-written one-liners. A list that long is edited by
# copy-paste and nobody diffs it, so generating them means adding an exam is
# one line in cka.sh and nothing here.
#
# Exam 1's commands have no suffix — 'exam', 'examreset', 'examhelp' — which
# is what they have always been. Its q/grade/solve/explain are deliberately
# NOT defined: those are the unnumbered verbs above, they default to exam 1
# when nothing is selected, and shadowing them would break 'cka use'.
_cka_define_numbered() {
  local n suffix
  for n in $(seq 1 "$CKA_COUNT"); do
    suffix="$n"; [ "$n" = "1" ] && suffix=""
    eval "
      exam${suffix}()      { \"\$CKA_EXAMS/exam${n}.sh\" \"\$@\"; }
      exam${suffix}reset() { \"\$CKA_EXAMS/setup${n}.sh\"; }
      exam${suffix}help()  { \"\$CKA_EXAMS/exam${n}.sh\" help; }
    "
    [ "$n" = "1" ] && continue
    eval "
      q${n}()       { \"\$CKA_EXAMS/exam${n}.sh\" q \"\$@\"; }
      grade${n}()   { \"\$CKA_EXAMS/exam${n}.sh\" grade \"\$@\"; }
      solve${n}()   { \"\$CKA_EXAMS/exam${n}.sh\" solve \"\$@\"; }
      explain${n}() { \"\$CKA_EXAMS/exam${n}.sh\" explain \"\$@\"; }
    "
  done
}
_cka_define_numbered
unset -f _cka_define_numbered

# 'examhelp' is the unnumbered verb — the help for whatever is SELECTED — and
# the generator above just bound it to exam 1. Define it last so it wins.
examhelp() { "$EXAM_HOME/cka.sh" examhelp; }

# ── per-exam extras ─────────────────────────────────────────
# Each exam has its own dashboard under a name that describes what it shows,
# and the three destructive ones have a restore. 'info' is the alias that
# works everywhere, so you never have to remember which is which.
netcheck()      { "$CKA_EXAMS/exam4.sh" netcheck; }
nodeinfo()      { "$CKA_EXAMS/exam5.sh" nodeinfo; }
triage()        { "$CKA_EXAMS/exam6.sh" triage; }
storeinfo()     { "$CKA_EXAMS/exam7.sh" storeinfo; }
cplaneinfo()    { "$CKA_EXAMS/exam8.sh" cplaneinfo; }
workinfo()      { "$CKA_EXAMS/exam9.sh" workinfo; }
edgeinfo()      { "$CKA_EXAMS/exam10.sh" edgeinfo; }
kustinfo()      { "$CKA_EXAMS/exam11.sh" kustinfo; }

exam5restore()  { "$CKA_EXAMS/exam5.sh" restore; }
exam6restore()  { "$CKA_EXAMS/exam6.sh" restore; }
exam10restore() { "$CKA_EXAMS/exam10.sh" restore; }

# ── tab completion ──────────────────────────────────────────
if command -v complete >/dev/null 2>&1; then
  _exam_qnums() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(seq 1 13)" -- "$cur") )
  }
  complete -F _exam_qnums q grade solve explain
  for _n in $(seq 2 "$CKA_COUNT"); do
    complete -F _exam_qnums "q$_n" "grade$_n" "solve$_n" "explain$_n"
  done
  unset _n

  _cka_complete() {
    local cur prev names verbs
    cur="${COMP_WORDS[COMP_CWORD]}"; prev="${COMP_WORDS[COMP_CWORD-1]}"
    # Read the names out of cka.sh rather than repeating them here, so a new
    # exam completes without anyone remembering to edit this list too. That
    # list went stale twice.
    names="$(awk -F'|' '/^[0-9]+\|[a-z-]+\|exam/{printf "%s %s ",$1,$2}' \
               "$EXAM_HOME/cka.sh" 2>/dev/null)"
    verbs="use scores list q next grade explain solve info reset examhelp help version"
    case "$prev" in
      use)  COMPREPLY=( $(compgen -W "$names" -- "$cur") ) ;;
      cka)  COMPREPLY=( $(compgen -W "$verbs $names" -- "$cur") ) ;;
      q|grade|explain|solve) COMPREPLY=( $(compgen -W "$(seq 1 13)" -- "$cur") ) ;;
      *)    COMPREPLY=( $(compgen -W "$verbs" -- "$cur") ) ;;
    esac
  }
  complete -F _cka_complete cka
fi
