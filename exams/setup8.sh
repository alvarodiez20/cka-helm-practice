#!/usr/bin/env bash
# ============================================================
#  cka-practice · setup8.sh
#  Seeds the EIGHTH exam: cluster lifecycle — etcd backup and
#  restore, kubeadm, certificates, node maintenance.
#
#  Unlike exams 5 and 6 this one breaks NOTHING. Every task is
#  an operation you perform: take a snapshot, restore it into a
#  new directory, back up the PKI, renew a certificate, drain a
#  node. So setup here is mostly checking that the tools and
#  paths the tasks need are actually present, and telling you
#  clearly if they are not.
#
#  It must run on the control plane node: etcd's certificates
#  and the static pod manifests are local files.
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers8"
EX8="$BASE/exam8"
NODE="${CKA_NODE:-node01}"

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
printf "%s  Preparing exam 8%s %s(etcd, kubeadm, certificates)%s\n\n" "$BO" "$N" "$D" "$N"
printf "  %sThis exam breaks nothing. Every task is an operation you carry out.%s\n\n" "$D" "$N"

command -v kubectl >/dev/null || die "no kubectl found"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

mkdir -p "$ANS" "$EX8"

# ── What the tasks need, checked up front ───────────────────
MISSING=0

if [ -f /etc/kubernetes/manifests/etcd.yaml ]; then
  ok "etcd static pod manifest found"
else
  warn "no /etc/kubernetes/manifests/etcd.yaml — run this on the CONTROL PLANE node"
  MISSING=1
fi

if command -v etcdctl >/dev/null 2>&1; then
  ok "etcdctl $(ETCDCTL_API=3 etcdctl version 2>/dev/null | head -1 | awk '{print $3}')"
else
  warn "etcdctl is not on PATH."
  say "   ${D}Tasks 1-3 need it. On a kubeadm node it usually ships inside the${N}"
  say "   ${D}etcd image, so either install etcd-client or run etcdctl through${N}"
  say "   ${D}the container:${N}"
  say "   ${D}  apt-get install -y etcd-client${N}"
  say "   ${D}  kubectl -n kube-system exec etcd-\$(hostname) -- etcdctl ...${N}"
  MISSING=1
fi

command -v etcdutl >/dev/null 2>&1 \
  && ok "etcdutl present (the modern way to restore a snapshot)" \
  || say "  ${D}etcdutl not found — 'etcdctl snapshot restore' still works, with a${N}
  ${D}deprecation notice on newer versions.${N}"

if command -v kubeadm >/dev/null 2>&1; then
  ok "kubeadm $(kubeadm version -o short 2>/dev/null)"
else
  warn "kubeadm not found — tasks 6, 7 and 10 need it"
  MISSING=1
fi

if [ -d /etc/kubernetes/pki/etcd ]; then
  ok "etcd PKI directory found"
else
  warn "no /etc/kubernetes/pki/etcd — task 5 needs it"
  MISSING=1
fi

if kubectl get node "$NODE" >/dev/null 2>&1; then
  ok "worker node '$NODE' found (tasks 8 and 9)"
else
  warn "node '$NODE' not found — set CKA_NODE=<name> for the drain tasks"
  MISSING=1
fi

# ── Something to notice going missing during a drain ────────
ns_wipe drain-lab
ns_make drain-lab
kubectl -n drain-lab create deployment parked --image=nginx:alpine --replicas=2 >/dev/null 2>&1
kubectl -n drain-lab patch deployment parked --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"10m","memory":"16Mi"}}}]' >/dev/null 2>&1
kubectl uncordon "$NODE" >/dev/null 2>&1
ok "namespace 'drain-lab' seeded with a 2-replica Deployment"

rm -f "$ANS"/*.txt "$EX8/.drained" 2>/dev/null

cat > "$EX8/README.txt" <<EOF
Exam 8 — etcd, kubeadm, certificates, node maintenance

Nothing is broken. Every task is an operation you perform.

Paths and commands you will need:

  /etc/kubernetes/manifests/etcd.yaml     where etcd's flags live
  /etc/kubernetes/pki/etcd/               etcd's CA, server cert and key
  /etc/kubernetes/manifests/              all four control plane static pods

  export ETCDCTL_API=3
  etcdctl --endpoints=https://127.0.0.1:2379 \\
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \\
    --cert=/etc/kubernetes/pki/etcd/server.crt \\
    --key=/etc/kubernetes/pki/etcd/server.key \\
    snapshot save /path/to/snap.db

  etcdutl snapshot status /path/to/snap.db --write-out=table
  etcdutl snapshot restore /path/to/snap.db --data-dir=/var/lib/etcd-restored

  kubeadm certs check-expiration
  kubeadm certs renew <name>
  kubeadm upgrade plan
  kubeadm token create --print-join-command

  kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data
  kubectl uncordon $NODE

IMPORTANT — why the restore task uses a NEW directory:

  A real etcd restore replaces /var/lib/etcd and needs the API server
  stopped while it happens. That would take kubectl down, and the grader
  with it. Task 3 therefore restores into /var/lib/etcd-restored, which is
  exactly the first half of the real procedure and is what the exam usually
  asks for. The walkthrough covers the cutover you would do next.

Answer files go in $ANS
EOF
ok "notes written to $EX8/README.txt"

if [ "$MISSING" = "1" ]; then
  echo
  warn "some prerequisites are missing — see the notes above."
  say "  ${D}Tasks needing them will simply not pass; the rest work fine.${N}"
fi

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
printf "    %scka use cluster%s   %s# select this exam%s\n" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s\n\n" "$BO" "$N" "$D" "$N"
printf "  %sTasks 8 and 9 are a pair: drain, then uncordon. Do them together.%s\n\n" "$D" "$N"
