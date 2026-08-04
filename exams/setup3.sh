#!/usr/bin/env bash
# ============================================================
#  cka-practice · setup3.sh
#  Seeds the THIRD Helm exam.
#
#  Unlike exams 1 and 2, this one runs against REAL public
#  chart repositories and a real OCI registry, because that is
#  what the current CKA actually asks for (Argo CD, CRDs,
#  oci:// installs). It therefore needs internet access.
#
#  It uses its own namespaces (argocd, demo, limbo) and its own
#  answer directories (~/answers3, ~/exam3), so it coexists
#  with setup1.sh and setup2.sh.
# ============================================================
set -uo pipefail

BASE="${HOME}"
EX3="$BASE/exam3"
ANS="$BASE/answers3"

# Every repo and version the exam pins. Historical chart versions never
# leave a repo index, so these stay valid.
ARGO_URL="https://argoproj.github.io/argo-helm"
TRAEFIK_URL="https://traefik.github.io/charts"
NGINX_URL="https://kubernetes.github.io/ingress-nginx"
PODINFO_URL="https://stefanprodan.github.io/podinfo"
PODINFO_OCI="oci://ghcr.io/stefanprodan/charts/podinfo"

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
printf "%s  Preparing Helm exam 3%s %s(real charts — needs internet)%s\n\n" "$BO" "$N" "$D" "$N"

# ── 1. Requirements ─────────────────────────────────────────
command -v kubectl >/dev/null || die "no kubectl found: run this on a node with a cluster (Killercoda, kind, minikube)"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

if ! command -v helm >/dev/null; then
  warn "helm is not installed, installing it..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 \
    || die "could not install helm; install it manually and run setup3.sh again"
fi
ok "helm $(helm version --short 2>/dev/null || echo '?')"

# This exam is useless without egress, so fail loudly and early rather than
# letting every task mysteriously score zero.
curl -fsS --max-time 15 "${PODINFO_URL}/index.yaml" -o /dev/null 2>/dev/null \
  || die "no internet access to ${PODINFO_URL}
      exam 3 installs from real public repositories and an OCI registry.
      If this environment is offline, use exam 1 or exam 2 (cka use helm-core),
      which serve their charts from localhost."
ok "public chart repositories reachable"

mkdir -p "$ANS" "$EX3"

# ── 2. Clean slate ──────────────────────────────────────────
# Remove anything a previous attempt left behind, releases first so Helm
# does not keep orphaned release secrets around.
for spec in "argocd argocd" "web demo" "oci-web demo" "stuck-report limbo"; do
  set -- $spec
  helm uninstall "$1" -n "$2" --wait=false >/dev/null 2>&1
done
kubectl delete crd -l app.kubernetes.io/part-of=argocd --ignore-not-found >/dev/null 2>&1
for c in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
  kubectl delete crd "$c" --ignore-not-found >/dev/null 2>&1
done
# The tasks ask the candidate to register these, so they must NOT be present.
for r in argo traefik ingress-nginx podinfo; do
  helm repo remove "$r" >/dev/null 2>&1
done
rm -rf "$EX3" "$ANS"; mkdir -p "$EX3" "$ANS"
ns_wipe argocd demo limbo
ok "previous state removed (namespaces, releases, CRDs, repos)"

# ── 3. Seed the stuck release for task 9 ────────────────────
# A release in 'pending-install' is what you get when a helm install is
# interrupted: the release record exists, 'helm list' hides it, and the name
# is taken. Reproduce it the way it happens in real life — start the install
# with --wait and kill helm before it finishes.
say "seeding a release stuck in pending-install (~15s)..."
ns_make limbo
helm repo add _seed3 "$PODINFO_URL" >/dev/null 2>&1
helm repo update _seed3 >/dev/null 2>&1

# 'set +m' disables job control so bash does not print its own
# "line 99: 6366 Killed  helm install ..." notice when we kill the job.
set +m
{ helm install stuck-report _seed3/podinfo --version 6.7.0 -n limbo \
    --wait --timeout 5m >/dev/null 2>&1 & } 2>/dev/null
SEED_PID=$!
sleep 6
kill -9 "$SEED_PID" >/dev/null 2>&1
pkill -9 -f "helm install stuck-report" >/dev/null 2>&1
wait "$SEED_PID" 2>/dev/null
sleep 2

# --pending works on Helm 3 and Helm 4 alike. Helm 4 removed -a/--all (it
# lists every status by default), so '-a' here would be a hard error and make
# a successful seed look like a failure.
stuck_status(){ helm list -n limbo --pending 2>/dev/null | grep -o 'pending-install'; }

if [ -z "$(stuck_status)" ]; then
  # Killing helm did not land it in pending-install (timing varies by cluster).
  # Rewrite the release record directly. Helm stores it as
  # base64(base64(gzip(json))) in a Secret, and 'helm list' filters on the
  # Secret's 'status' label, so both have to change.
  SEC="$(kubectl get secret -n limbo -o name 2>/dev/null | grep 'sh.helm.release.v1.stuck-report' | head -1)"
  if [ -n "$SEC" ] && command -v python3 >/dev/null; then
    python3 - "$SEC" <<'PY' >/dev/null 2>&1
import base64, gzip, json, subprocess, sys
sec = sys.argv[1]
raw = subprocess.check_output(
    ["kubectl", "get", sec, "-n", "limbo", "-o", "jsonpath={.data.release}"])
rel = json.loads(gzip.decompress(base64.b64decode(base64.b64decode(raw))))
rel["info"]["status"] = "pending-install"
enc = base64.b64encode(base64.b64encode(
    gzip.compress(json.dumps(rel).encode()))).decode()
subprocess.check_call(["kubectl", "patch", sec, "-n", "limbo", "--type=merge",
                       "-p", json.dumps({"data": {"release": enc}})])
subprocess.check_call(["kubectl", "label", sec, "-n", "limbo",
                       "status=pending-install", "--overwrite"])
PY
  fi
fi

if [ -n "$(stuck_status)" ]; then
  ok "release 'stuck-report' seeded in pending-install (namespace limbo)"
else
  warn "could not force pending-install; task 9 may already look solved"
fi
helm repo remove _seed3 >/dev/null 2>&1

# ── 4. A note file, so the pinned versions are never a guess ─
cat > "$EX3/README.txt" <<EOF
Exam 3 works against real, public chart sources:

  argo           $ARGO_URL
  traefik        $TRAEFIK_URL
  ingress-nginx  $NGINX_URL
  podinfo        $PODINFO_URL
  podinfo (OCI)  $PODINFO_OCI

Registering the repositories is part of the tasks — they are deliberately
not configured for you. Files you are asked to produce go in:

  $ANS      answers the grader reads
  $EX3        values files and charts you author
EOF
ok "notes written to $EX3/README.txt"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"

SRC_LINE="source ${ROOT}/activate.sh"
if [ -f "${ROOT}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

echo
printf "%s  Done.%s Load the commands into this shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "  Then, from any directory:\n\n"
printf "    %scka use helm-oci%s   %s# select this exam%s
" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s

" "$BO" "$N" "$D" "$N"
printf "  %sExams 1 and 2 stay available alongside it.%s\n" "$D" "$N"
printf "  %sIf the Killercoda session expires, run %s/setup3.sh again.%s\n\n" "$D" "$HERE" "$N"
