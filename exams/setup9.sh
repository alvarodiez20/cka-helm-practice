#!/usr/bin/env bash
# ============================================================
#  cka-practice · setup9.sh
#  Seeds the NINTH exam: workloads and scheduling.
#
#  Workloads & Scheduling is 15% of the CKA and was the last
#  domain this suite only covered in passing. Nothing here is
#  destructive — the seed is a few Deployments to roll, scale
#  and constrain.
# ============================================================
set -uo pipefail

BASE="${HOME}"; ANS="$BASE/answers9"; EX9="$BASE/exam9"
NS="work-lab"
IMG="${CKA_W9_IMAGE:-nginx:alpine}"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
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
say(){ printf "  %s\n" "$*"; }

echo
printf "%s  Preparing exam 9%s %s(workloads and scheduling)%s\n\n" "$BO" "$N" "$D" "$N"

command -v kubectl >/dev/null || die "no kubectl found"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

NODES="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${NODES:-0}" -lt 2 ]; then
  warn "only $NODES node — tasks 7 and 8 (anti-affinity, topology spread) can be"
  say "   ${D}written correctly but the pods cannot actually spread. They are${N}"
  say "   ${D}graded on the spec, so they still pass.${N}"
else
  ok "$NODES nodes — spreading tasks will behave for real"
fi

kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1 \
  && ok "metrics-server present — the HPA will have metrics to read" \
  || warn "no metrics-server: the HPA in task 6 is graded on its spec, and will
      report <unknown> targets. That is expected, not a fault."

mkdir -p "$ANS" "$EX9"
ns_wipe "$NS"
kubectl delete priorityclass high-urgency --ignore-not-found >/dev/null 2>&1
rm -rf "$ANS" "$EX9"; mkdir -p "$ANS" "$EX9"
ns_make "$NS"
ok "namespace '$NS' created fresh"

# Task 1: a Deployment with real history to roll back through. Three
# revisions, the last one broken, so 'rollout undo' has somewhere to go.
kubectl -n "$NS" create deployment shop --image="$IMG" --replicas=2 >/dev/null 2>&1
kubectl -n "$NS" patch deployment shop --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"10m","memory":"16Mi"}}}]' >/dev/null 2>&1
kubectl -n "$NS" rollout status deploy/shop --timeout=90s >/dev/null 2>&1
kubectl -n "$NS" set image deploy/shop nginx=nginx:1.27-alpine >/dev/null 2>&1
kubectl -n "$NS" rollout status deploy/shop --timeout=90s >/dev/null 2>&1
kubectl -n "$NS" set image deploy/shop nginx=nginx:9.99-broken >/dev/null 2>&1
ok "deployment 'shop' seeded with 3 revisions, the newest one broken"

# Tasks 6, 10: something to autoscale and to protect.
kubectl -n "$NS" create deployment api --image="$IMG" --replicas=3 >/dev/null 2>&1
kubectl -n "$NS" patch deployment api --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"50m","memory":"32Mi"}}}]' >/dev/null 2>&1
kubectl -n "$NS" rollout status deploy/api --timeout=90s >/dev/null 2>&1
ok "deployment 'api' seeded with 3 replicas and CPU requests"

cat > "$EX9/README.txt" <<EOF
Exam 9 — workloads and scheduling

Namespace: $NS

What is here:

  deploy/shop   3 revisions; the current one uses a broken image tag (task 1)
  deploy/api    3 replicas, 50m CPU requested each (tasks 6 and 10)

Nothing is broken except deployment 'shop', and that is deliberate.

The commands this exam is about:

  kubectl -n $NS rollout history deploy/shop
  kubectl -n $NS rollout history deploy/shop --revision=2
  kubectl -n $NS rollout undo deploy/shop
  kubectl -n $NS rollout status deploy/shop

  kubectl create job / cronjob --help
  kubectl autoscale deploy api --min=2 --max=5 --cpu-percent=70
  kubectl -n $NS get hpa,pdb,job,cronjob

Note on the HPA: without metrics-server it will show <unknown> as the current
utilisation and will not scale. The object is still correct, and that is what
is graded.

Answer files go in $ANS
EOF
ok "notes written to $EX9/README.txt"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
SRC_LINE="source ${ROOT}/activate.sh"
if [ -f "${ROOT}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

echo
printf "%s  Done.%s  %s\n\n" "$G$BO" "$N" "$SRC_LINE"
printf "    %scka use workloads%s   %s# select this exam%s\n" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s\n\n" "$BO" "$N" "$D" "$N"
