#!/usr/bin/env bash
# ============================================================
#  cka-practice · setup5.sh
#  Seeds the FIFTH exam: worker node failure troubleshooting.
#
#  This one DELIBERATELY BREAKS a worker node — it stops the
#  kubelet, corrupts its config and its kubeconfig, cordons and
#  taints the node. Every file it touches is backed up first,
#  and 'exam5restore' puts everything back.
#
#  It needs:
#    - a cluster with at least one worker node
#    - passwordless ssh from here to that node (Killercoda has it)
#    - root on the node, to edit kubelet config and use systemctl
#
#  Do NOT run this against anything you care about.
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers5"
EX5="$BASE/exam5"
NODE="${CKA_NODE:-node01}"
SRV_IMAGE="${CKA_N5_IMAGE:-nginx:alpine}"

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
printf "%s  Preparing exam 5%s %s(worker node failure troubleshooting)%s\n\n" "$BO" "$N" "$D" "$N"
printf "  %sThis breaks a worker node on purpose. Backups are taken, and%s\n" "$Y" "$N"
printf "  %s'exam5restore' undoes everything.%s\n\n" "$Y" "$N"

# ── 1. Requirements ─────────────────────────────────────────
command -v kubectl >/dev/null || die "no kubectl found"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"

kubectl get node "$NODE" >/dev/null 2>&1 \
  || die "node '$NODE' not found.
      This exam needs a worker node to break. Set CKA_NODE to its name:
        CKA_NODE=<name> ./setup5.sh
      Nodes in this cluster:
$(kubectl get nodes -o name 2>/dev/null | sed 's/^/        /')"

# A single-node cluster would mean breaking the control plane, which is a
# different exam and a much worse idea.
if [ "$(kubectl get nodes -o name 2>/dev/null | wc -l)" -lt 2 ]; then
  die "only one node in this cluster. Exam 5 breaks a WORKER node; on a
      single-node cluster that is the control plane. Use a two-node cluster
      (the Killercoda CKA playground has controlplane + node01)."
fi
ok "cluster reachable, target node '$NODE' exists"

SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
onnode(){ $SSH "$NODE" "$@"; }

onnode true >/dev/null 2>&1 \
  || die "cannot ssh to '$NODE' without a password.
      Exam 5 has to stop the kubelet and edit files on the node, which needs
      ssh. On Killercoda 'ssh $NODE' works out of the box. Set CKA_NODE if
      your worker has a different name."
ok "passwordless ssh to '$NODE' works"

onnode "systemctl cat kubelet >/dev/null 2>&1" \
  || die "no kubelet systemd unit on '$NODE' — is it really a kubeadm node?"
ok "kubelet unit found on '$NODE'"

mkdir -p "$ANS" "$EX5"

# ── 2. Back everything up, on the node ──────────────────────
# Restoring has to work even if the candidate mangles the files further, so
# the backup is taken once and kept out of the way. If a backup already
# exists we leave it alone: it is from the pristine cluster, and a second
# setup run would otherwise back up the already-broken files.
BK="/root/.cka-exam5-backup"
onnode "
  set -e
  mkdir -p $BK
  for f in /var/lib/kubelet/config.yaml /etc/kubernetes/kubelet.conf; do
    b=$BK/\$(basename \$f)
    [ -f \"\$b\" ] || cp -a \"\$f\" \"\$b\"
  done
  systemctl is-enabled kubelet > $BK/was-enabled 2>/dev/null || true
" || die "could not create backups on '$NODE'"
ok "kubelet config and kubeconfig backed up to $NODE:$BK"

# ── 3. Clean up any previous run of this exam ────────────────
ns_wipe node-lab
kubectl taint node "$NODE" maintenance- >/dev/null 2>&1
kubectl label node "$NODE" disktype- >/dev/null 2>&1
kubectl uncordon "$NODE" >/dev/null 2>&1
onnode "rm -f /etc/kubernetes/manifests-exam5/*.yaml 2>/dev/null" >/dev/null 2>&1
rm -rf "$ANS" "$EX5"; mkdir -p "$ANS" "$EX5"
ok "previous exam 5 state cleared"

# ── 4. Workloads that the scheduling tasks act on ───────────
ns_make node-lab

# Task 5: nodeSelector disktype=ssd, and the node does not have that label.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ssd-only
  namespace: node-lab
spec:
  replicas: 1
  selector:
    matchLabels: {app: ssd-only}
  template:
    metadata:
      labels: {app: ssd-only}
    spec:
      nodeSelector:
        disktype: ssd
      containers:
        - name: c
          image: $SRV_IMAGE
          resources:
            requests: {cpu: 10m, memory: 16Mi}
EOF

# Task 8: a request no node can satisfy, so the pod stays Pending with a
# clear scheduler event. 64 CPUs is comfortably impossible on a lab node.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: greedy
  namespace: node-lab
spec:
  replicas: 1
  selector:
    matchLabels: {app: greedy}
  template:
    metadata:
      labels: {app: greedy}
    spec:
      containers:
        - name: c
          image: $SRV_IMAGE
          resources:
            requests: {cpu: "64", memory: 16Mi}
EOF

# Task 7: a DaemonSet with no control-plane toleration, so it lands on the
# worker only. Making it run everywhere is the task.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: node-lab
spec:
  selector:
    matchLabels: {app: node-agent}
  template:
    metadata:
      labels: {app: node-agent}
    spec:
      containers:
        - name: c
          image: busybox:1.36
          command: ["sleep", "86400"]
          resources:
            requests: {cpu: 10m, memory: 16Mi}
EOF
ok "workloads seeded in namespace 'node-lab'"

# ── 5. Scheduling-level faults ──────────────────────────────
kubectl cordon "$NODE" >/dev/null 2>&1
kubectl taint node "$NODE" maintenance=true:NoSchedule --overwrite >/dev/null 2>&1
ok "'$NODE' cordoned and tainted maintenance=true:NoSchedule"

# ── 6. Break the kubelet, in three stacked layers ───────────
# They surface one at a time, which is the point: fixing the first reveals
# the second. Same shape as the KodeKloud worker-node practice tests and as
# the real exam's "the cluster is broken again" tasks.
#
#   layer 1  the service is stopped and disabled      -> nothing running
#   layer 2  clientCAFile points at a missing file    -> crashloops on start
#   layer 3  kubelet.conf points at port 6553         -> runs, cannot register
say "breaking the kubelet on '$NODE' (three stacked faults)..."
onnode "
  set -e
  systemctl stop kubelet
  systemctl disable kubelet >/dev/null 2>&1
  sed -i 's#clientCAFile: /etc/kubernetes/pki/ca.crt#clientCAFile: /etc/kubernetes/pki/WRONG-CA-FILE.crt#' \
    /var/lib/kubelet/config.yaml
  sed -i 's#:6443#:6553#' /etc/kubernetes/kubelet.conf
  # Task 6: staticPodPath removed, so a manifest alone will not be picked up.
  sed -i '/^staticPodPath:/d' /var/lib/kubelet/config.yaml
  mkdir -p /etc/kubernetes/manifests-exam5
" || die "could not apply the kubelet faults on '$NODE'"

# Prove each fault actually landed, rather than trusting sed.
planted=0
onnode "grep -q 'WRONG-CA-FILE.crt' /var/lib/kubelet/config.yaml" && planted=$((planted+1)) \
  || warn "the clientCAFile fault did not apply (unexpected config layout?)"
onnode "grep -q ':6553' /etc/kubernetes/kubelet.conf" && planted=$((planted+1)) \
  || warn "the kubeconfig port fault did not apply"
onnode "! grep -q '^staticPodPath:' /var/lib/kubelet/config.yaml" && planted=$((planted+1)) \
  || warn "staticPodPath is still set"
onnode "! systemctl is-active --quiet kubelet" && planted=$((planted+1)) \
  || warn "kubelet is somehow still active"
ok "$planted of 4 kubelet faults planted"

say "waiting for the API server to notice (~40s)..."
for i in $(seq 1 20); do
  st="$(kubectl get node "$NODE" --no-headers 2>/dev/null | awk '{print $2}')"
  case "$st" in *NotReady*) break ;; esac
  sleep 3
done
st="$(kubectl get node "$NODE" --no-headers 2>/dev/null | awk '{print $2}')"
case "$st" in
  *NotReady*) ok "'$NODE' is now $st — as intended" ;;
  *) warn "'$NODE' still reports '$st'; it may take another minute to go NotReady" ;;
esac

# ── 7. Notes and the restore script ─────────────────────────
cat > "$EX5/README.txt" <<EOF
Exam 5 — worker node failure troubleshooting

Target node: $NODE

What has been done to it, so you can put it back by hand if you want to:

  - kubelet stopped AND disabled
  - /var/lib/kubelet/config.yaml   clientCAFile -> a file that does not exist
  - /var/lib/kubelet/config.yaml   staticPodPath line deleted
  - /etc/kubernetes/kubelet.conf   API server port 6443 -> 6553
  - node cordoned (SchedulingDisabled)
  - node tainted maintenance=true:NoSchedule

Pristine copies of both files are on the node at:
  $BK

Namespace 'node-lab' holds:
  deploy/ssd-only    nodeSelector disktype=ssd, which no node has
  deploy/greedy      requests 64 CPUs, which no node can satisfy
  ds/node-agent      no control-plane toleration, so it skips controlplane

Getting onto the node:
  ssh $NODE
  systemctl status kubelet
  journalctl -u kubelet -n 50 --no-pager
  systemctl cat kubelet          # shows which config files it reads

Put everything back:
  exam5restore                   (or ./exam5.sh restore)

Answer files go in $ANS
EOF

cat > "$EX5/restore.sh" <<EOF
#!/usr/bin/env bash
# Restores '$NODE' to the state it was in before setup5.sh ran.
set -uo pipefail
NODE="$NODE"
BK="$BK"
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
echo
echo "  restoring \$NODE from \$BK ..."
\$SSH "\$NODE" "
  set -e
  [ -f \$BK/config.yaml ]  && cp -a \$BK/config.yaml  /var/lib/kubelet/config.yaml
  [ -f \$BK/kubelet.conf ] && cp -a \$BK/kubelet.conf /etc/kubernetes/kubelet.conf
  systemctl enable kubelet >/dev/null 2>&1 || true
  systemctl restart kubelet
" || { echo "  could not restore over ssh"; exit 1; }
kubectl uncordon "\$NODE" >/dev/null 2>&1
kubectl taint node "\$NODE" maintenance- >/dev/null 2>&1
kubectl label node "\$NODE" disktype- >/dev/null 2>&1
kubectl delete ns node-lab --ignore-not-found --wait=false >/dev/null 2>&1
echo "  waiting for \$NODE to go Ready ..."
for i in \$(seq 1 30); do
  s="\$(kubectl get node "\$NODE" --no-headers 2>/dev/null | awk '{print \$2}')"
  [ "\$s" = "Ready" ] && { echo "  \$NODE is Ready"; exit 0; }
  sleep 3
done
echo "  \$NODE is still not Ready — check 'ssh \$NODE journalctl -u kubelet -n 50'"
EOF
chmod +x "$EX5/restore.sh"
ok "notes in $EX5/README.txt, restore script in $EX5/restore.sh"

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
printf "    %scka use nodes%s   %s# select this exam%s
" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s

" "$BO" "$N" "$D" "$N"
printf "  %sStart with 'kubectl get nodes' and 'ssh %s'.%s\n" "$D" "$NODE" "$N"
printf "  %sIf the Killercoda session expires, run %s/setup5.sh again.%s\n\n" "$D" "$HERE" "$N"
