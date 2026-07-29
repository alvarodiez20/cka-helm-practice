#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam.sh
#  13 preguntas tipo CKA sobre Helm. 100 puntos. Aprobado: 66.
#
#    ./exam.sh            lista las preguntas
#    ./exam.sh q 4        enunciado de la 4
#    ./exam.sh grade      corrige todo y da la nota
#    ./exam.sh grade 4    corrige solo la 4
#    ./exam.sh solve 4    solucion de la 4
#    ./exam.sh reset      vuelve a sembrar el entorno (llama a setup.sh)
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers"
REPO_NAME="ckarepo"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

TOTAL=13
declare -A Q PTS SOL

Q[1]="La aplicacion 'frontend' debe desplegarse en el namespace 'web', que TODAVIA NO
EXISTE. Instalala desde el chart ${REPO_NAME}/demo-app en su version 0.2.0,
con 3 replicas.
El nombre de la release debe ser exactamente 'frontend'."
PTS[1]=7
SOL[1]="helm install frontend ${REPO_NAME}/demo-app --version 0.2.0 \\
  -n web --create-namespace --set replicaCount=3"

Q[2]="La release 'legacy' del namespace 'apps' se actualizo por error a una imagen que
no existe y sus pods no arrancan.
Devuelvela al estado de la ultima revision que SI funcionaba, usando el historial
de Helm. No la reinstales ni la borres."
PTS[2]=8
SOL[2]="helm history legacy -n apps          # localiza la ultima revision buena (la 2)
helm rollback legacy 2 -n apps
# o simplemente, al ser la inmediatamente anterior:
helm rollback legacy -n apps"

Q[3]="Existe una release llamada 'ghost' en algun punto del cluster, pero no sabes en
que namespace.
Averigualo y escribe UNICAMENTE el nombre del namespace en el fichero
${ANS}/q3.txt"
PTS[3]=6
SOL[3]="helm list -A | grep ghost
echo hidden-77 > ${ANS}/q3.txt"

Q[4]="Actualiza la release 'frontend' a la version 0.3.0 del chart, CONSERVANDO los
values que ya tiene configurados (no debe perder sus 3 replicas)."
PTS[4]=7
SOL[4]="helm upgrade frontend ${REPO_NAME}/demo-app --version 0.3.0 -n web --reuse-values
# tambien vale volver a pasar --set replicaCount=3"

Q[5]="Genera en ${ANS}/q5.yaml los manifiestos que produciria el chart
${REPO_NAME}/demo-app 0.3.0 con replicaCount=5, SIN instalar nada en el cluster
y sin modificar ninguna release existente."
PTS[5]=8
SOL[5]="helm template demo ${REPO_NAME}/demo-app --version 0.3.0 \\
  --set replicaCount=5 > ${ANS}/q5.yaml"

Q[6]="Vuelca en ${ANS}/q6.txt TODOS los values con los que corre la release
'frontend', incluidos los valores por defecto del chart que tu no has tocado."
PTS[6]=7
SOL[6]="helm get values frontend -n web -a > ${ANS}/q6.txt"

Q[7]="Retira del cluster la release 'ghost' pero CONSERVANDO su historial, para poder
recuperarla mas adelante."
PTS[7]=7
SOL[7]="helm uninstall ghost -n hidden-77 --keep-history"

Q[8]="Recupera la release 'ghost': debe volver a estar desplegada.
Hazlo a partir de su historial, sin reinstalarla desde el repositorio."
PTS[8]=8
SOL[8]="helm list -n hidden-77 --uninstalled     # ver la ultima revision
helm rollback ghost -n hidden-77"

Q[9]="Crea desde cero un chart llamado 'mychart' en ${BASE}/mychart.
La version del CHART debe ser 1.2.0 y la version de la APLICACION 3.4.5.
El chart debe pasar 'helm lint' sin errores."
PTS[9]=10
SOL[9]="cd ${BASE} && helm create mychart
sed -i 's/^version:.*/version: 1.2.0/' mychart/Chart.yaml
sed -i 's/^appVersion:.*/appVersion: \"3.4.5\"/' mychart/Chart.yaml
helm lint ./mychart"

Q[10]="Empaqueta el chart 'mychart' y deja el fichero .tgz resultante dentro del
directorio ${BASE}/dist/"
PTS[10]=7
SOL[10]="mkdir -p ${BASE}/dist
helm package ${BASE}/mychart -d ${BASE}/dist"

Q[11]="Instala el chart EMPAQUETADO del punto anterior como release 'mine' en el
namespace 'dev', que no existe. El comando no debe darse por terminado hasta
que los recursos esten listos."
PTS[11]=8
SOL[11]="helm install mine ${BASE}/dist/mychart-1.2.0.tgz \\
  -n dev --create-namespace --wait"

Q[12]="La release 'frontend' debe pasar a usar la etiqueta de imagen 1.25, y Helm debe
guardarla como CADENA de texto, no como numero.
Aplica el upgrade correspondiente sin perder el resto de su configuracion."
PTS[12]=9
SOL[12]="helm upgrade frontend ${REPO_NAME}/demo-app -n web --reuse-values \\
  --set-string image.tag=1.25
# con --set image.tag=1.25 Helm lo guardaria como numero y la comprobacion falla"

Q[13]="El chart ${BASE}/mychart debe declarar como dependencia el chart 'demo-app'
version 0.3.0 del repositorio '${REPO_NAME}', y esa dependencia debe estar
descargada dentro del chart."
PTS[13]=8
SOL[13]="cat >> ${BASE}/mychart/Chart.yaml <<'EOF'
dependencies:
  - name: demo-app
    version: 0.3.0
    repository: http://127.0.0.1:8879
EOF
helm dependency update ${BASE}/mychart"

# ─────────── helpers de correccion ───────────
hfield(){ # release ns campo  -> valor
  helm list -n "$2" --filter "^$1\$" -o json 2>/dev/null \
    | tr '{},' '\n' | grep "\"$3\":" | head -1 | cut -d'"' -f4
}
hnum(){ local v; v="$(hfield "$1" "$2" "$3")"; echo "${v:-0}"; }
huninstalled(){ helm list -n "$2" --uninstalled -o json 2>/dev/null | grep -q "\"$1\""; }
hvals(){ helm get values "$1" -n "$2" ${3:-} -o json 2>/dev/null; }
nsexists(){ kubectl get ns "$1" >/dev/null 2>&1; }
filehas(){ [ -f "$1" ] && grep -q "$2" "$1"; }

check(){
  case "$1" in
    1) nsexists web \
       && [ "$(hfield frontend web status)" = "deployed" ] \
       && hvals frontend web | grep -q '"replicaCount":3' \
       && helm history frontend -n web -o json 2>/dev/null | grep -q 'demo-app-0.2.0' ;;
    2) [ "$(hfield legacy apps status)" = "deployed" ] \
       && [ "$(hnum legacy apps revision)" -ge 4 ] \
       && ! hvals legacy apps | grep -q 'no-existe-esta-tag' ;;
    3) [ -f "$ANS/q3.txt" ] \
       && [ "$(tr -d '[:space:]' < "$ANS/q3.txt")" = "hidden-77" ] ;;
    4) [ "$(hfield frontend web chart)" = "demo-app-0.3.0" ] \
       && hvals frontend web | grep -q '"replicaCount":3' ;;
    5) filehas "$ANS/q5.yaml" "kind: Deployment" \
       && filehas "$ANS/q5.yaml" "replicas: 5" \
       && hvals frontend web | grep -q '"replicaCount":3' ;;
    6) filehas "$ANS/q6.txt" "replicaCount" \
       && filehas "$ANS/q6.txt" "pullPolicy" \
       && filehas "$ANS/q6.txt" "service" ;;
    7) helm history ghost -n hidden-77 -o json 2>/dev/null | grep -q 'uninstalled' ;;
    8) [ "$(hfield ghost hidden-77 status)" = "deployed" ] \
       && [ "$(hnum ghost hidden-77 revision)" -ge 3 ] ;;
    9) [ -f "$BASE/mychart/Chart.yaml" ] \
       && grep -Eq '^version:[[:space:]]*1\.2\.0[[:space:]]*$' "$BASE/mychart/Chart.yaml" \
       && grep -Eq '^appVersion:[[:space:]]*"?3\.4\.5"?[[:space:]]*$' "$BASE/mychart/Chart.yaml" \
       && helm lint "$BASE/mychart" >/dev/null 2>&1 ;;
    10) ls "$BASE"/dist/mychart-1.2.0.tgz >/dev/null 2>&1 ;;
    11) nsexists dev \
       && [ "$(hfield mine dev status)" = "deployed" ] \
       && [ "$(hfield mine dev chart)" = "mychart-1.2.0" ] ;;
    12) hvals frontend web | grep -q '"tag":"1.25"' ;;
    13) grep -q 'demo-app' "$BASE/mychart/Chart.yaml" 2>/dev/null \
       && ls "$BASE"/mychart/charts/demo-app-0.3.0.tgz >/dev/null 2>&1 ;;
    *) return 2 ;;
  esac
}

show(){
  printf "\n%s┌─ Pregunta %s/%s ─ %s puntos%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N"
  printf "%s└%s\n" "$B" "$N"
  echo "${Q[$1]}"
  printf "\n%s  cuando la termines:  ./exam.sh grade %s%s\n\n" "$D" "$1" "$N"
}

grade_one(){
  local n="$1"
  if check "$n"; then
    printf "  %s✔%s  %2s  %-3s pts   %s\n" "$G" "$N" "$n" "${PTS[$n]}" "correcto"
    return 0
  else
    printf "  %s✘%s  %2s  %-3s pts   %s\n" "$R" "$N" "$n" "0" "sin resolver o incompleto"
    return 1
  fi
}

grade_all(){
  local got=0 max=0 i
  printf "\n%s  Correccion%s\n\n" "$BO" "$N"
  for i in $(seq 1 $TOTAL); do
    max=$(( max + ${PTS[$i]} ))
    if grade_one "$i"; then got=$(( got + ${PTS[$i]} )); fi
  done
  local pct=$(( got * 100 / max ))
  printf "\n  %sNOTA: %s/%s  (%s%%)%s   " "$BO" "$got" "$max" "$pct" "$N"
  if [ "$pct" -ge 66 ]; then printf "%sAPROBADO%s\n\n" "$G$BO" "$N"
  else printf "%sSUSPENSO%s %s(el CKA se aprueba con 66)%s\n\n" "$R$BO" "$N" "$D" "$N"; fi
}

case "${1:-list}" in
  list)
    printf "\n%s  Examen de Helm para el CKA%s — %s preguntas · 100 puntos · aprobado 66\n\n" "$BO" "$N" "$TOTAL"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s./exam.sh q N   ·   ./exam.sh grade   ·   ./exam.sh solve N%s\n\n" "$D" "$N" ;;
  q|show) show "${2:?falta el numero de pregunta}" ;;
  grade)
    if [ $# -ge 2 ]; then printf "\n"; grade_one "$2"; printf "\n"
    else grade_all; fi ;;
  solve)
    n="${2:?falta el numero}"
    printf "\n%s  Solucion de la %s:%s\n\n%s\n\n" "$Y" "$n" "$N" "${SOL[$n]}" ;;
  reset) bash "$HERE/setup.sh" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
