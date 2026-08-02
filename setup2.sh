#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · setup2.sh
#  Seeds the SECOND Helm exam. It uses its own local repo
#  (port 8880), its own namespaces and its own answers
#  directory, so it coexists with setup.sh.
# ============================================================
set -uo pipefail

BASE="${HOME}"
LAB="$BASE/cka-helm2"
CHARTS="$LAB/charts"
SRC="$LAB/src"
EX2="$BASE/exam2"
ANS="$BASE/answers2"
PORT="${CKA_HELM2_PORT:-8880}"
REPO_NAME="extrarepo"
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
printf "%s  Preparing Helm exam 2%s\n\n" "$BO" "$N"

# ── 1. Requirements ─────────────────────────────────────────
command -v kubectl >/dev/null || die "no kubectl found: run this on a node with a cluster (Killercoda, kind, minikube)"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

if ! command -v helm >/dev/null; then
  warn "helm is not installed, installing it..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 \
    || die "could not install helm; install it manually and run setup2.sh again"
fi
ok "helm $(helm version --short 2>/dev/null || echo '?')"

command -v python3 >/dev/null || die "python3 is required to serve the local chart repo"

# ── 2. The 'web-stack' chart, in 3 versions ─────────────────
rm -rf "$LAB" "$EX2"; mkdir -p "$CHARTS" "$SRC" "$EX2" "$ANS"

build_chart(){ # $1 = version, $2 = appVersion
  local v="$1" av="$2" d="$SRC/web-stack"
  rm -rf "$d"; mkdir -p "$d/templates"
  cat > "$d/Chart.yaml" <<EOF
apiVersion: v2
name: web-stack
description: Practice chart for the second CKA Helm exam
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
ingress:
  enabled: false
  host: web.example.local
env:
  TIER: base
resources: {}
EOF
  cat > "$d/templates/_helpers.tpl" <<'EOF'
{{- define "web-stack.name" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
EOF
  cat > "$d/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "web-stack.name" . }}
  labels:
    app: {{ include "web-stack.name" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "web-stack.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "web-stack.name" . }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: TIER
              value: "{{ .Values.env.TIER }}"
          ports:
            - containerPort: 80
EOF
  cat > "$d/templates/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "web-stack.name" . }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ include "web-stack.name" . }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 80
EOF
  helm package "$d" -d "$CHARTS" >/dev/null 2>&1 || die "failed to package web-stack $v"
}

build_chart 1.0.0 1.0.0
build_chart 1.1.0 1.1.0
build_chart 2.0.0 2.0.0
helm repo index "$CHARTS" >/dev/null 2>&1
ok "chart web-stack packaged in 3 versions (1.0.0, 1.1.0, 2.0.0)"

# ── 3. Local repo server ────────────────────────────────────
pkill -f "http.server ${PORT}" >/dev/null 2>&1
nohup python3 -m http.server "$PORT" --directory "$CHARTS" >/dev/null 2>&1 &
sleep 1
curl -sf "$REPO_URL/index.yaml" >/dev/null || die "the local repo is not responding at $REPO_URL"
ok "local repo serving at $REPO_URL"

# We add it so we can seed, then remove it at the end:
# adding it back is task 1.
helm repo remove "$REPO_NAME" >/dev/null 2>&1
helm repo add "$REPO_NAME" "$REPO_URL" >/dev/null 2>&1 || die "could not add the repo"
helm repo update >/dev/null 2>&1

# ── 4. Initial state ────────────────────────────────────────
ns_wipe api stage broken-77 shop
ns_make stage broken-77

# 'stage-app': three revisions, each with different values, so a specific
# revision can be fished out of the history.
helm install stage-app "$REPO_NAME/web-stack" --version 1.0.0 -n stage \
  --set replicaCount=1 --set env.TIER=one >/dev/null 2>&1
helm upgrade stage-app "$REPO_NAME/web-stack" --version 1.0.0 -n stage \
  --set replicaCount=2 --set env.TIER=two >/dev/null 2>&1
helm upgrade stage-app "$REPO_NAME/web-stack" --version 1.1.0 -n stage \
  --set replicaCount=3 --set env.TIER=three >/dev/null 2>&1
ok "release 'stage-app' seeded in stage (3 revisions, different values)"

# 'checkout': ends up genuinely in failed state (--wait + missing image)
say "seeding a failed release (this takes ~20s)..."
helm install checkout "$REPO_NAME/web-stack" --version 1.0.0 -n broken-77 \
  --set image.tag=does-not-exist-tag --wait --timeout 20s >/dev/null 2>&1
ok "release 'checkout' seeded in failed state"

# ── 5. Local charts for tasks 9 and 12 ──────────────────────

# parentchart: declares web-stack as a subchart and vendors it, so task 12
# works even before the repo has been added back.
mkdir -p "$EX2/parentchart/templates"
cat > "$EX2/parentchart/Chart.yaml" <<EOF
apiVersion: v2
name: parentchart
description: Parent chart with web-stack as a subchart
type: application
version: 1.0.0
appVersion: "1.0.0"
dependencies:
  - name: web-stack
    version: 1.0.0
    repository: ${REPO_URL}
EOF
cat > "$EX2/parentchart/values.yaml" <<'EOF'
# A subchart's values are nested under its name.
web-stack:
  replicaCount: 1
EOF
cat > "$EX2/parentchart/templates/configmap.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-parent
data:
  owner: parentchart
EOF
helm dependency update "$EX2/parentchart" >/dev/null 2>&1 \
  || warn "could not vendor the parentchart subchart"
ok "chart 'parentchart' created with web-stack as a subchart"

# brokenchart: does not pass 'helm lint'. Three faults planted on purpose.
mkdir -p "$EX2/brokenchart/templates"
cat > "$EX2/brokenchart/Chart.yaml" <<'EOF'
name: brokenchart
description: This chart does not pass helm lint. Fix it.
type: application
version: not-a-version
appVersion: "1.0.0"
EOF
cat > "$EX2/brokenchart/values.yaml" <<'EOF'
replicaCount: 1
image:
  repository: nginx
  tag: "1.25-alpine"
EOF
# Mind the indentation of 'image': it is wrong on purpose (the 3rd fault,
# and it does not surface until Chart.yaml is fixed, because before that Helm
# never gets as far as rendering the templates).
cat > "$EX2/brokenchart/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-brokenchart
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}-brokenchart
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-brokenchart
    spec:
      containers:
        - name: app
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
EOF
ok "chart 'brokenchart' created (broken on purpose)"

# ── 6. Values files for task 4 ──────────────────────────────
cat > "$EX2/base.yaml" <<'EOF'
replicaCount: 3
env:
  TIER: base
EOF
cat > "$EX2/override.yaml" <<'EOF'
replicaCount: 5
EOF
ok "base.yaml and override.yaml created in $EX2"

# ── 7. Remove the repo: adding it back is task 1 ────────────
helm repo remove "$REPO_NAME" >/dev/null 2>&1
ok "repo '$REPO_NAME' removed on purpose (that is task 1)"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Make the exam commands available in every new shell.
SRC_LINE="source ${HERE}/activate.sh"
if [ -f "${HERE}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-helm-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

echo
printf "%s  Done.%s Load the commands into this shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "  Then, from any directory:\n\n"
printf "    %scka use helm-values%s   %s# select this exam%s
" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s

" "$BO" "$N" "$D" "$N"
printf "  %sExam 1 stays available alongside it: exam, q, grade...%s\n" "$D" "$N"
printf "  %sIf the Killercoda session expires, run %s/setup2.sh again.%s\n\n" "$D" "$HERE" "$N"
