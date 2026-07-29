#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · setup.sh
#  Prepara un entorno de examen de Helm sobre un cluster real
#  (Killercoda, kind, minikube...). Todo offline salvo las
#  imagenes de los pods.
# ============================================================
set -uo pipefail

BASE="${HOME}"
LAB="$BASE/cka-helm"
CHARTS="$LAB/charts"
SRC="$LAB/src"
PORT="${CKA_HELM_PORT:-8879}"
REPO_NAME="ckarepo"
REPO_URL="http://127.0.0.1:${PORT}"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
say(){ printf "  %s\n" "$*"; }
ok(){ printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){ printf "  ${R}✘${N} %s\n" "$*"; exit 1; }

echo
printf "%s  Preparando el entorno de examen de Helm%s\n\n" "$BO" "$N"

# ── 1. Requisitos ───────────────────────────────────────────
command -v kubectl >/dev/null || die "no hay kubectl: ejecuta esto en un nodo con cluster (Killercoda, kind, minikube)"
kubectl get nodes >/dev/null 2>&1 || die "kubectl no puede hablar con ningun cluster"
ok "cluster accesible"

if ! command -v helm >/dev/null; then
  warn "helm no esta instalado, instalandolo..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 \
    || die "no he podido instalar helm; instalalo a mano y vuelve a ejecutar setup.sh"
fi
ok "helm $(helm version --short 2>/dev/null || echo '?')"

command -v python3 >/dev/null || die "hace falta python3 para servir el repo local de charts"

# ── 2. Chart de practica, en 3 versiones ────────────────────
rm -rf "$LAB"; mkdir -p "$CHARTS" "$SRC" "$BASE/answers"

build_chart(){ # $1 = version, $2 = appVersion
  local v="$1" av="$2" d="$SRC/demo-app"
  rm -rf "$d"; mkdir -p "$d/templates"
  cat > "$d/Chart.yaml" <<EOF
apiVersion: v2
name: demo-app
description: Chart de practica para el examen de Helm del CKA
type: application
version: $v
appVersion: "$av"
EOF
  cat > "$d/values.yaml" <<'EOF'
replicaCount: 1
image:
  repository: nginx
  tag: "1.25-alpine"
  pullPolicy: IfNotPresent
service:
  type: ClusterIP
  port: 80
resources: {}
EOF
  cat > "$d/templates/_helpers.tpl" <<'EOF'
{{- define "demo-app.name" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
EOF
  cat > "$d/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "demo-app.name" . }}
  labels:
    app: {{ include "demo-app.name" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "demo-app.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "demo-app.name" . }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
EOF
  cat > "$d/templates/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "demo-app.name" . }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ include "demo-app.name" . }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 80
EOF
  helm package "$d" -d "$CHARTS" >/dev/null 2>&1 || die "fallo al empaquetar demo-app $v"
}

build_chart 0.1.0 1.0.0
build_chart 0.2.0 1.1.0
build_chart 0.3.0 2.0.0
helm repo index "$CHARTS" >/dev/null 2>&1
ok "chart demo-app empaquetado en 3 versiones (0.1.0, 0.2.0, 0.3.0)"

# ── 3. Servidor del repo local ──────────────────────────────
pkill -f "http.server ${PORT}" >/dev/null 2>&1
nohup python3 -m http.server "$PORT" --directory "$CHARTS" >/dev/null 2>&1 &
sleep 1
curl -sf "$REPO_URL/index.yaml" >/dev/null || die "el repo local no responde en $REPO_URL"
ok "repo local sirviendo en $REPO_URL"

helm repo remove "$REPO_NAME" >/dev/null 2>&1
helm repo add "$REPO_NAME" "$REPO_URL" >/dev/null 2>&1 || die "no he podido anadir el repo"
helm repo update >/dev/null 2>&1
ok "repo '$REPO_NAME' anadido"

# ── 4. Estado inicial del examen ────────────────────────────
for ns in apps hidden-77 web dev; do kubectl delete ns "$ns" --ignore-not-found --wait=false >/dev/null 2>&1; done
sleep 3
kubectl create ns apps      >/dev/null 2>&1
kubectl create ns hidden-77 >/dev/null 2>&1

# 'legacy': tres revisiones, la actual apunta a una imagen que no existe
helm install legacy "$REPO_NAME/demo-app" --version 0.1.0 -n apps \
  --set replicaCount=1 >/dev/null 2>&1
helm upgrade legacy "$REPO_NAME/demo-app" --version 0.2.0 -n apps \
  --set replicaCount=2 >/dev/null 2>&1
helm upgrade legacy "$REPO_NAME/demo-app" --version 0.2.0 -n apps \
  --set replicaCount=2 --set image.tag=no-existe-esta-tag >/dev/null 2>&1
ok "release 'legacy' sembrada en el namespace apps (3 revisiones, la ultima rota)"

# 'ghost': escondida en un namespace poco obvio
helm install ghost "$REPO_NAME/demo-app" --version 0.1.0 -n hidden-77 >/dev/null 2>&1
ok "release 'ghost' sembrada en un namespace que tendras que encontrar"

mkdir -p "$BASE/answers"
echo
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Deja los comandos del examen cargados en cada shell nueva.
SRC_LINE="source ${HERE}/activate.sh"
if [ -f "${HERE}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-helm-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "comandos del examen anadidos a ~/.bashrc"
fi

printf "%s  Listo.%s Carga los comandos en este shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "  Y a partir de ahi, desde cualquier directorio:\n\n"
printf "    exam           %s# ver las 13 preguntas%s\n" "$D" "$N"
printf "    q 1            %s# leer una pregunta%s\n" "$D" "$N"
printf "    grade          %s# corregir y ver tu nota sobre 100%s\n" "$D" "$N"
printf "    explain 1      %s# resolucion paso a paso%s\n" "$D" "$N"
printf "    examhelp       %s# ayuda completa%s\n\n" "$D" "$N"
printf "  %sEn shells nuevas ya se cargan solos. Si reinicias la sesion de%s\n" "$D" "$N"
printf "  %sKillercoda, vuelve a ejecutar %s/setup.sh%s\n\n" "$D" "$HERE" "$N"
