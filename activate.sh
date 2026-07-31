#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · activate.sh
#  Defines the exam commands in YOUR shell, so you never have
#  to type ./exam.sh or sit in the repo directory.
#
#    source ~/cka-helm-practice/activate.sh
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
#  Names:  helm-core helm-values helm-oci netpol nodes
#          tshoot storage cluster workloads
#
#  The old numbered commands (exam6, q6 4, grade7 ...) still work and are
#  defined below, so nothing breaks mid-session.
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

# ── the original per-exam commands, unchanged ───────────────
# We invoke the scripts directly so their shebang (env bash) decides which
# bash runs them, rather than whichever bash happens to be first in PATH.
exam()       { "$EXAM_HOME/exam.sh" "$@"; }
examhelp()   { "$EXAM_HOME/exam.sh" help; }
examreset()  { "$EXAM_HOME/setup.sh"; }

exam2()      { "$EXAM_HOME/exam2.sh" "$@"; }
q2()         { "$EXAM_HOME/exam2.sh" q "$@"; }
grade2()     { "$EXAM_HOME/exam2.sh" grade "$@"; }
solve2()     { "$EXAM_HOME/exam2.sh" solve "$@"; }
explain2()   { "$EXAM_HOME/exam2.sh" explain "$@"; }
exam2help()  { "$EXAM_HOME/exam2.sh" help; }
exam2reset() { "$EXAM_HOME/setup2.sh"; }

exam3()      { "$EXAM_HOME/exam3.sh" "$@"; }
q3()         { "$EXAM_HOME/exam3.sh" q "$@"; }
grade3()     { "$EXAM_HOME/exam3.sh" grade "$@"; }
solve3()     { "$EXAM_HOME/exam3.sh" solve "$@"; }
explain3()   { "$EXAM_HOME/exam3.sh" explain "$@"; }
exam3help()  { "$EXAM_HOME/exam3.sh" help; }
exam3reset() { "$EXAM_HOME/setup3.sh"; }

exam4()      { "$EXAM_HOME/exam4.sh" "$@"; }
q4()         { "$EXAM_HOME/exam4.sh" q "$@"; }
grade4()     { "$EXAM_HOME/exam4.sh" grade "$@"; }
solve4()     { "$EXAM_HOME/exam4.sh" solve "$@"; }
explain4()   { "$EXAM_HOME/exam4.sh" explain "$@"; }
netcheck()   { "$EXAM_HOME/exam4.sh" netcheck; }
exam4help()  { "$EXAM_HOME/exam4.sh" help; }
exam4reset() { "$EXAM_HOME/setup4.sh"; }

exam5()        { "$EXAM_HOME/exam5.sh" "$@"; }
q5()           { "$EXAM_HOME/exam5.sh" q "$@"; }
grade5()       { "$EXAM_HOME/exam5.sh" grade "$@"; }
solve5()       { "$EXAM_HOME/exam5.sh" solve "$@"; }
explain5()     { "$EXAM_HOME/exam5.sh" explain "$@"; }
nodeinfo()     { "$EXAM_HOME/exam5.sh" nodeinfo; }
exam5restore() { "$EXAM_HOME/exam5.sh" restore; }
exam5help()    { "$EXAM_HOME/exam5.sh" help; }
exam5reset()   { "$EXAM_HOME/setup5.sh"; }

exam6()        { "$EXAM_HOME/exam6.sh" "$@"; }
q6()           { "$EXAM_HOME/exam6.sh" q "$@"; }
grade6()       { "$EXAM_HOME/exam6.sh" grade "$@"; }
solve6()       { "$EXAM_HOME/exam6.sh" solve "$@"; }
explain6()     { "$EXAM_HOME/exam6.sh" explain "$@"; }
triage()       { "$EXAM_HOME/exam6.sh" triage; }
exam6restore() { "$EXAM_HOME/exam6.sh" restore; }
exam6help()    { "$EXAM_HOME/exam6.sh" help; }
exam6reset()   { "$EXAM_HOME/setup6.sh"; }

exam7()      { "$EXAM_HOME/exam7.sh" "$@"; }
q7()         { "$EXAM_HOME/exam7.sh" q "$@"; }
grade7()     { "$EXAM_HOME/exam7.sh" grade "$@"; }
solve7()     { "$EXAM_HOME/exam7.sh" solve "$@"; }
explain7()   { "$EXAM_HOME/exam7.sh" explain "$@"; }
storeinfo()  { "$EXAM_HOME/exam7.sh" storeinfo; }
exam7help()  { "$EXAM_HOME/exam7.sh" help; }
exam7reset() { "$EXAM_HOME/setup7.sh"; }

exam8()      { "$EXAM_HOME/exam8.sh" "$@"; }
q8()         { "$EXAM_HOME/exam8.sh" q "$@"; }
grade8()     { "$EXAM_HOME/exam8.sh" grade "$@"; }
solve8()     { "$EXAM_HOME/exam8.sh" solve "$@"; }
explain8()   { "$EXAM_HOME/exam8.sh" explain "$@"; }
cplaneinfo() { "$EXAM_HOME/exam8.sh" cplaneinfo; }
exam8help()  { "$EXAM_HOME/exam8.sh" help; }
exam8reset() { "$EXAM_HOME/setup8.sh"; }

exam9()      { "$EXAM_HOME/exam9.sh" "$@"; }
q9()         { "$EXAM_HOME/exam9.sh" q "$@"; }
grade9()     { "$EXAM_HOME/exam9.sh" grade "$@"; }
solve9()     { "$EXAM_HOME/exam9.sh" solve "$@"; }
explain9()   { "$EXAM_HOME/exam9.sh" explain "$@"; }
workinfo()   { "$EXAM_HOME/exam9.sh" workinfo; }
exam9help()  { "$EXAM_HOME/exam9.sh" help; }
exam9reset() { "$EXAM_HOME/setup9.sh"; }

# Tab completion: task numbers.
if command -v complete >/dev/null 2>&1; then
  _exam_qnums() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(seq 1 13)" -- "$cur") )
  }
  complete -F _exam_qnums q grade solve explain
  complete -F _exam_qnums q2 grade2 solve2 explain2
  complete -F _exam_qnums q3 grade3 solve3 explain3
  complete -F _exam_qnums q4 grade4 solve4 explain4
  complete -F _exam_qnums q5 grade5 solve5 explain5
  complete -F _exam_qnums q6 grade6 solve6 explain6
  complete -F _exam_qnums q7 grade7 solve7 explain7
  complete -F _exam_qnums q8 grade8 solve8 explain8
  complete -F _exam_qnums q9 grade9 solve9 explain9

  _cka_complete() {
    local cur prev names verbs
    cur="${COMP_WORDS[COMP_CWORD]}"; prev="${COMP_WORDS[COMP_CWORD-1]}"
    names="helm-core helm-values helm-oci netpol nodes tshoot storage cluster workloads 1 2 3 4 5 6 7 8 9"
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
