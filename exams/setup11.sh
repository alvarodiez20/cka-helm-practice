#!/usr/bin/env bash
# ============================================================
#  cka-practice · setup11.sh
#  Seeds the ELEVENTH exam: Kustomize.
#
#  "Use Helm and Kustomize to install cluster components" is a
#  named competency under Cluster Architecture, Installation
#  and Configuration — 25% of the CKA — and this suite covered
#  only the Helm half of it for its first ten releases.
#
#  Nothing here is destructive. The seed lays out loose
#  manifests with no kustomization.yaml (writing it is task 1)
#  and one deliberately broken kustomization with three stacked
#  faults (task 12).
# ============================================================
set -uo pipefail

BASE="${HOME}"; ANS="$BASE/answers11"; EX11="$BASE/exam11"
NS="kust-lab"
IMG="${CKA_K11_IMAGE:-nginx:alpine}"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
ok(){ printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){ printf "  ${R}✘${N} %s\n" "$*"; exit 1; }
say(){ printf "  %s\n" "$*"; }

# ── Namespace lifecycle ─────────────────────────────────────
# Namespaces terminate asynchronously, and creating one while it is still
# Terminating fails. With kubectl output suppressed that failure is invisible:
# the seed carries on, everything destined for that namespace silently fails
# to be created, and the script still reports success. So: wait for the
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
printf "%s  Preparing exam 11%s %s(Kustomize)%s\n\n" "$BO" "$N" "$D" "$N"

command -v kubectl >/dev/null || die "no kubectl found"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

# Kustomize is BUILT IN to kubectl (since 1.14) — there is nothing to install,
# and on the exam there is no standalone 'kustomize' binary to reach for. But
# which version is embedded matters: 'labels:' with 'pairs' arrived in
# kustomize v5 / kubectl 1.27, and task 3 depends on it.
KVER="$(kubectl version --client 2>/dev/null | sed -n 's/.*[Kk]ustomize Version: *v*\([0-9][0-9.]*\).*/\1/p' | head -1)"
if [ -n "$KVER" ]; then
  ok "kubectl has kustomize v${KVER} built in"
  case "$KVER" in
    [0-4].*) warn "task 3 uses 'labels:' with 'pairs', which needs kustomize v5
      ${D}(kubectl 1.27+). On this version use 'commonLabels' — and read
      explain 3, because commonLabels also rewrites the selector.${N}" ;;
  esac
else
  warn "could not read the embedded kustomize version from 'kubectl version --client'"
fi

if ! kubectl kustomize --help >/dev/null 2>&1; then
  die "'kubectl kustomize' is not available — this kubectl is too old for this exam"
fi

mkdir -p "$ANS" "$EX11"
ns_wipe "$NS"
rm -rf "$ANS" "$EX11"
mkdir -p "$ANS" "$EX11/base" "$EX11/overlays" "$EX11/broken"
ns_make "$NS"
ok "namespace '$NS' created fresh"

# ── base/: loose manifests, deliberately with NO kustomization.yaml ──
# Writing that file is task 1. Both manifests are plain, unprefixed and
# namespace-less on purpose: every transformation the exam asks for has to
# come from the kustomization, not from editing these.
cat > "$EX11/base/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: shop
  template:
    metadata:
      labels:
        app: shop
    spec:
      containers:
        - name: web
          image: ${IMG}
          ports:
            - containerPort: 80
EOF

cat > "$EX11/base/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: shop
spec:
  selector:
    app: shop
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF
ok "base manifests written to $EX11/base (no kustomization.yaml — that is task 1)"

# ── broken/: three stacked faults, surfacing one at a time ───
# Same shape as exam 5's kubelet task: each fix reveals the next error, which
# is how a real 'kubectl apply -k' session actually goes.
#   1. kind: Kustomize          -> Kustomization
#   2. resources: deploy.yaml   -> deployment.yaml (the file is not called that)
#   3. namePrefix as a list     -> a scalar
cat > "$EX11/broken/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reports
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reports
  template:
    metadata:
      labels:
        app: reports
    spec:
      containers:
        - name: web
          image: ${IMG}
EOF

cat > "$EX11/broken/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: reports
spec:
  selector:
    app: reports
  ports:
    - port: 80
      targetPort: 80
EOF

cat > "$EX11/broken/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomize

namePrefix:
  - batch-

resources:
  - deploy.yaml
  - service.yaml
EOF
ok "a kustomization with three stacked faults written to $EX11/broken (task 12)"

cat > "$EX11/README.txt" <<EOF
Exam 11 — Kustomize

Namespace: $NS
Working tree: $EX11
Answer files: $ANS

What is here:

  base/deployment.yaml    Deployment 'shop', 2 replicas, image ${IMG}
  base/service.yaml       Service 'shop' on port 80
  base/                   NO kustomization.yaml — writing it is task 1

  overlays/               empty — task 9 creates overlays/prod here

  broken/                 a kustomization.yaml with three faults (task 12).
                          Each one hides the next, so fix, re-run, repeat:
                            kubectl kustomize $EX11/broken

THE RULE THAT MAKES THIS EXAM AN EXAM

  Every transformation is graded on the RENDERED or APPLIED result AND on the
  base manifests being untouched. Editing base/deployment.yaml to change the
  image or the replica count scores zero, because the whole point of Kustomize
  is that you do not.

The commands this exam is about:

  kubectl kustomize $EX11/base              render, print, apply nothing
  kubectl apply -k $EX11/base               render and apply
  kubectl kustomize $EX11/overlays/prod
  kubectl apply -k $EX11/overlays/prod
  kubectl kustomize --help

  There is no 'kustomize' binary on the exam. It is built into kubectl, and
  '-k' is the flag that means "this path is a kustomization directory".

Order matters:

  1 before 2      you cannot apply a kustomization you have not written
  2 before 3-8    those change the applied result and are graded live
  9 before 10,11  the overlay has to exist before you can patch through it
  13 last         it counts what the overlay renders, which 9-11 change
EOF
ok "notes written to $EX11/README.txt"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
SRC_LINE="source ${ROOT}/activate.sh"
if [ -f "${ROOT}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

echo
printf "%s  Done.%s  %s\n\n" "$G$BO" "$N" "$SRC_LINE"
printf "    %scka use kustomize%s   %s# select this exam%s\n" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s\n\n" "$BO" "$N" "$D" "$N"
