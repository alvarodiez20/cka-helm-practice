#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · activate.sh
#  Defines the exam commands in YOUR shell, so you never have
#  to type ./exam.sh or sit in the repo directory.
#
#    source ~/cka-helm-practice/activate.sh
#
#  Exam 1:  exam      q 4      grade   grade 4
#           examhelp  explain 4         solve 4     examreset
#
#  Exam 2:  exam2     q2 4     grade2  grade2 4
#           exam2help explain2 4       solve2 4    exam2reset
#
#  Exam 3:  exam3     q3 4     grade3  grade3 4
#           exam3help explain3 4       solve3 4    exam3reset
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

# We invoke the scripts directly so their shebang (env bash) decides which
# bash runs them, rather than whichever bash happens to be first in PATH.
exam()       { "$EXAM_HOME/exam.sh" "$@"; }
q()          { "$EXAM_HOME/exam.sh" q "$@"; }
grade()      { "$EXAM_HOME/exam.sh" grade "$@"; }
solve()      { "$EXAM_HOME/exam.sh" solve "$@"; }
explain()    { "$EXAM_HOME/exam.sh" explain "$@"; }
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

# Tab completion: task numbers.
if command -v complete >/dev/null 2>&1; then
  _exam_qnums() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(seq 1 13)" -- "$cur") )
  }
  complete -F _exam_qnums q grade solve explain
  complete -F _exam_qnums q2 grade2 solve2 explain2
  complete -F _exam_qnums q3 grade3 solve3 explain3
fi
