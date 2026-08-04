#!/usr/bin/env bash
# ============================================================
#  cka-practice · setup1.sh
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

# ── Namespace lifecycle ─────────────────────────────────────
# Namespaces terminate asynchronously, and creating one while it is still
# Terminating fails. With kubectl output suppressed that failure is invisible:
# the seed carries on, every workload destined for that namespace silently
# fails to be created, and the script still reports success. So: wait for the
# deletes to finish, force the finalizers off if something is wedged, and fail
# loudly if a namespace still cannot be created.
ns_wipe(){ # ns...
  local ns still i
  for ns in "$@"; do
    kubectl delete ns "$ns" --ignore-not-found --wait=false >/dev/null 2>&1
  done
  still=""
  for i in $(seq 1 120); do            # up to 4 minutes
    still=""
    for ns in "$@"; do
      kubectl get ns "$ns" >/dev/null 2>&1 && still="$still $ns"
    done
    [ -z "$still" ] && return 0
    sleep 2
  done
  warn "namespaces still Terminating after 4 min:$still"
  warn "forcing their finalizers off"
  for ns in $still; do
    kubectl get ns "$ns" -o json 2>/dev/null \
      | tr -d '\n' | sed 's/"finalizers": *\[[^]]*\]/"finalizers": []/' \
      | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - >/dev/null 2>&1
  done
  sleep 5
}

ns_make(){ # ns...
  # NOTE: "kubectl get ns" SUCCEEDS for a namespace that is Terminating, so
  # existence is not the test — the phase is. A Terminating namespace cannot
  # hold objects, so treat it as fatal rather than carrying on into a seed
  # that will quietly create nothing.
  local ns out phase
  for ns in "$@"; do
    phase="$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)"
    [ "$phase" = "Active" ] && continue
    [ -n "$phase" ] && die "namespace '$ns' is stuck in $phase — delete it by hand, then re-run"
    out="$(kubectl create ns "$ns" 2>&1)" \
      || die "could not create namespace '$ns': $out"
  done
}

echo
printf "%s  Preparing the Helm exam environment%s\n\n" "$BO" "$N"

# ── 1. Requirements ─────────────────────────────────────────
command -v kubectl >/dev/null || die "no kubectl found: run this on a node with a cluster (Killercoda, kind, minikube)"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

if ! command -v helm >/dev/null; then
  warn "helm is not installed, installing it..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 \
    || die "could not install helm; install it manually and run setup1.sh again"
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
ns_wipe apps hidden-77 web dev
ns_make apps hidden-77

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
ROOT="$(cd -- "$HERE/.." && pwd)"

# Make the exam commands available in every new shell.
SRC_LINE="source ${ROOT}/activate.sh"
if [ -f "${ROOT}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

printf "%s  Done.%s Load the commands into this shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "  Then, from any directory:\n\n"
printf "    %scka use helm-core%s   %s# select this exam%s
" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s

" "$BO" "$N" "$D" "$N"
printf "  %sNew shells load them automatically. If the Killercoda session%s\n" "$D" "$N"
printf "  %sexpires, run %s/setup1.sh again.%s\n\n" "$D" "$HERE" "$N"
