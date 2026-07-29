#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · setup.sh
#  Prepares a Helm exam environment on a real cluster
#  (Killercoda, kind, minikube...). Fully offline except for
#  the pod images.
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
printf "%s  Preparing the Helm exam environment%s\n\n" "$BO" "$N"

# ── 1. Requirements ─────────────────────────────────────────
command -v kubectl >/dev/null || die "no kubectl found: run this on a node with a cluster (Killercoda, kind, minikube)"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

if ! command -v helm >/dev/null; then
  warn "helm is not installed, installing it..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 \
    || die "could not install helm; install it manually and run setup.sh again"
fi
ok "helm $(helm version --short 2>/dev/null || echo '?')"

command -v python3 >/dev/null || die "python3 is required to serve the local chart repo"

# ── 2. Practice chart, in 3 versions ────────────────────────
rm -rf "$LAB"; mkdir -p "$CHARTS" "$SRC" "$BASE/answers"

build_chart(){ # $1 = version, $2 = appVersion
  local v="$1" av="$2" d="$SRC/demo-app"
  rm -rf "$d"; mkdir -p "$d/templates"
  cat > "$d/Chart.yaml" <<EOF
apiVersion: v2
name: demo-app
description: Practice chart for the CKA Helm exam
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
  helm package "$d" -d "$CHARTS" >/dev/null 2>&1 || die "failed to package demo-app $v"
}

build_chart 0.1.0 1.0.0
build_chart 0.2.0 1.1.0
build_chart 0.3.0 2.0.0
helm repo index "$CHARTS" >/dev/null 2>&1
ok "chart demo-app packaged in 3 versions (0.1.0, 0.2.0, 0.3.0)"

# ── 3. Local repo server ────────────────────────────────────
pkill -f "http.server ${PORT}" >/dev/null 2>&1
nohup python3 -m http.server "$PORT" --directory "$CHARTS" >/dev/null 2>&1 &
sleep 1
curl -sf "$REPO_URL/index.yaml" >/dev/null || die "the local repo is not responding at $REPO_URL"
ok "local repo serving at $REPO_URL"

helm repo remove "$REPO_NAME" >/dev/null 2>&1
helm repo add "$REPO_NAME" "$REPO_URL" >/dev/null 2>&1 || die "could not add the repo"
helm repo update >/dev/null 2>&1
ok "repo '$REPO_NAME' added"

# ── 4. Initial exam state ───────────────────────────────────
for ns in apps hidden-77 web dev; do kubectl delete ns "$ns" --ignore-not-found --wait=false >/dev/null 2>&1; done
sleep 3
kubectl create ns apps      >/dev/null 2>&1
kubectl create ns hidden-77 >/dev/null 2>&1

# 'legacy': three revisions, the current one points at an image that does not exist
helm install legacy "$REPO_NAME/demo-app" --version 0.1.0 -n apps \
  --set replicaCount=1 >/dev/null 2>&1
helm upgrade legacy "$REPO_NAME/demo-app" --version 0.2.0 -n apps \
  --set replicaCount=2 >/dev/null 2>&1
helm upgrade legacy "$REPO_NAME/demo-app" --version 0.2.0 -n apps \
  --set replicaCount=2 --set image.tag=does-not-exist-tag >/dev/null 2>&1
ok "release 'legacy' seeded in namespace apps (3 revisions, the last one broken)"

# 'ghost': hidden in a non-obvious namespace
helm install ghost "$REPO_NAME/demo-app" --version 0.1.0 -n hidden-77 >/dev/null 2>&1
ok "release 'ghost' seeded in a namespace you will have to find"

mkdir -p "$BASE/answers"
echo
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Make the exam commands available in every new shell.
SRC_LINE="source ${HERE}/activate.sh"
if [ -f "${HERE}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-helm-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

printf "%s  Done.%s Load the commands into this shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "  Then, from any directory:\n\n"
printf "    exam           %s# list the 13 tasks%s\n" "$D" "$N"
printf "    q 1            %s# read a task%s\n" "$D" "$N"
printf "    grade          %s# grade and see your score out of 100%s\n" "$D" "$N"
printf "    explain 1      %s# step-by-step walkthrough%s\n" "$D" "$N"
printf "    examhelp       %s# full help%s\n\n" "$D" "$N"
printf "  %sNew shells load them automatically. If the Killercoda session%s\n" "$D" "$N"
printf "  %sexpires, run %s/setup.sh again.%s\n\n" "$D" "$HERE" "$N"
