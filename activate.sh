#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · activate.sh
#  Define los comandos del examen en TU shell, para no tener
#  que escribir ./exam.sh ni estar en el directorio del repo.
#
#    source ~/cka-helm-practice/activate.sh
#
#  A partir de ahi:
#    exam        q 4        grade       grade 4
#                solve 4    examreset
# ============================================================

# Este fichero hay que 'source'arlo, no ejecutarlo: si lo ejecutas, las
# funciones se definen en un subshell que muere al terminar.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "  esto hay que cargarlo en el shell actual:" >&2
  echo "      source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

EXAM_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export EXAM_HOME

# Invocamos los scripts directamente para que mande su shebang
# (env bash), no el bash que tengamos delante en el PATH.
exam()      { "$EXAM_HOME/exam.sh" "$@"; }
q()         { "$EXAM_HOME/exam.sh" q "$@"; }
grade()     { "$EXAM_HOME/exam.sh" grade "$@"; }
solve()     { "$EXAM_HOME/exam.sh" solve "$@"; }
examreset() { "$EXAM_HOME/setup.sh"; }

# Tab-completion: numeros de pregunta para q / grade / solve.
if command -v complete >/dev/null 2>&1; then
  _exam_qnums() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(seq 1 13)" -- "$cur") )
  }
  complete -F _exam_qnums q grade solve
fi
