#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · setup10.sh
#  Seeds the TENTH exam: Ingress, Gateway API, and the CNI.
#
#  This one DELIBERATELY BREAKS POD NETWORKING on a worker
#  node. It disables every CNI configuration file in
#  /etc/cni/net.d and plants an invalid one that sorts first,
#  which is what "cni plugin not initialized" actually looks
#  like in the field. The node goes NotReady and no new pod can
#  be created on it.
#
#  Everything it touches is backed up first and
#  'exam10restore' puts it back.
#
#  It needs:
#    - a cluster with at least one worker node
#    - passwordless ssh to that node (Killercoda has it)
#    - internet access, to fetch the Gateway API CRDs
#
#  Do NOT run this against anything you care about.
# ============================================================
set -uo pipefail

BASE="${HOME}"; ANS="$BASE/answers10"; EX10="$BASE/exam10"
NS="edge-lab"
NODE="${CKA_NODE:-node01}"
IMG="${CKA_E10_IMAGE:-nginx:alpine}"

# The Gateway API ships as plain CRDs with no controller. The standard
# channel is the GA/beta set: GatewayClass, Gateway, HTTPRoute, GRPCRoute
# and ReferenceGrant — which is exactly the set the CKA asks about.
GWVER="${CKA_GWAPI_VERSION:-v1.4.1}"
GWURL="${CKA_GWAPI_URL:-https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWVER}/standard-install.yaml}"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
say(){ printf "  %s\n" "$*"; }
ok(){ printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){ printf "  ${R}✘${N} %s\n" "$*"; exit 1; }

# ── Namespace lifecycle ─────────────────────────────────────
# Namespaces terminate asynchronously, and creating one while it is still
# Terminating fails. With kubectl output suppressed that failure is invisible:
# the seed carries on, every object destined for that namespace silently fails
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
  # existence is not the test — the phase is.
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
printf "%s  Preparing exam 10%s %s(Ingress, Gateway API, CNI)%s\n\n" "$BO" "$N" "$D" "$N"
printf "  %sThis breaks pod networking on '%s' on purpose. Backups are taken,%s\n" "$Y" "$NODE" "$N"
printf "  %sand 'exam10restore' undoes everything.%s\n\n" "$Y" "$N"

# ── 1. Requirements ─────────────────────────────────────────
command -v kubectl >/dev/null || die "no kubectl found"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"

kubectl get node "$NODE" >/dev/null 2>&1 \
  || die "node '$NODE' not found.
      This exam needs a worker node whose CNI it can break. Set CKA_NODE:
        CKA_NODE=<name> ./setup10.sh
      Nodes in this cluster:
$(kubectl get nodes -o name 2>/dev/null | sed 's/^/        /')"

if [ "$(kubectl get nodes -o name 2>/dev/null | wc -l)" -lt 2 ]; then
  die "only one node in this cluster. Exam 10 disables the CNI on a WORKER
      node; on a single-node cluster that is the control plane, which would
      take the API server with it. Use a two-node cluster (the Killercoda
      CKA playground has controlplane + node01)."
fi
ok "cluster reachable, target node '$NODE' exists"

SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
onnode(){ $SSH "$NODE" "$@"; }

onnode true >/dev/null 2>&1 \
  || die "cannot ssh to '$NODE' without a password.
      Exam 10 has to edit /etc/cni/net.d on the node, which needs ssh. On
      Killercoda 'ssh $NODE' works out of the box. Set CKA_NODE if your
      worker has a different name."
ok "passwordless ssh to '$NODE' works"

CNIDIR="/etc/cni/net.d"
onnode "[ -d $CNIDIR ]" \
  || die "$CNIDIR does not exist on '$NODE'. Is a CNI installed at all?"
CNIFILES="$(onnode "ls $CNIDIR 2>/dev/null" | tr '\n' ' ')"
ok "CNI config dir on '$NODE' currently holds: ${CNIFILES:-(nothing)}"

# ── 2. Gateway API CRDs ─────────────────────────────────────
# There is no controller anywhere in this exam and that is deliberate: the
# CKA asks you to WRITE Gateway API objects, and every task here is graded on
# the object you produced, not on traffic actually flowing through it. A
# Gateway that never reports an address is the expected state.
GWOK=0
if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  GWOK=1
  ok "Gateway API CRDs already installed"
else
  say "installing the Gateway API standard channel (${GWVER})..."
  if kubectl apply --server-side -f "$GWURL" >/dev/null 2>&1 \
     || kubectl apply -f "$GWURL" >/dev/null 2>&1; then
    GWOK=1
    ok "Gateway API CRDs installed from ${GWVER}"
  else
    warn "could not install the Gateway API CRDs from:"
    say "   ${D}${GWURL}${N}"
    say "   ${D}Tasks 6 to 9 need them. Install them by hand and re-run:${N}"
    say "   ${D}  kubectl apply --server-side -f ${GWURL}${N}"
    say "   ${D}Or point the seed elsewhere with CKA_GWAPI_URL=...${N}"
  fi
fi

# ── 3. Clean up any previous run ────────────────────────────
mkdir -p "$ANS" "$EX10"
ns_wipe "$NS"
kubectl delete ingressclass nginx-ext --ignore-not-found >/dev/null 2>&1
kubectl delete gatewayclass edge-class --ignore-not-found >/dev/null 2>&1
kubectl -n kube-system delete ds cni-agent --ignore-not-found >/dev/null 2>&1
rm -rf "$ANS" "$EX10"; mkdir -p "$ANS" "$EX10"
ok "previous exam 10 state cleared"

ns_make "$NS"
ok "namespace '$NS' created fresh"

# ── 4. Backends ─────────────────────────────────────────────
# Every pod here tolerates not-ready and unreachable FOR EVER. That is not
# decoration: task 11 takes the node NotReady, and the default 300-second
# eviction toleration would otherwise start deleting these pods five minutes
# in, on a node where nothing new can be scheduled. The exam would then look
# broken rather than faulted. It is also the same trick a real CNI DaemonSet
# uses, for the same reason — see task 13.
mkpod(){ # name image port
  kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $1
  namespace: $NS
  labels: {app: $1}
spec:
  replicas: 1
  selector:
    matchLabels: {app: $1}
  template:
    metadata:
      labels: {app: $1}
    spec:
      tolerations:
        - key: node.kubernetes.io/not-ready
          operator: Exists
          effect: NoExecute
        - key: node.kubernetes.io/unreachable
          operator: Exists
          effect: NoExecute
      containers:
        - name: c
          image: $2
          ports: [{containerPort: $3}]
          resources:
            requests: {cpu: 10m, memory: 16Mi}
EOF
}

mkpod shop-v1 "$IMG" 80
mkpod shop-v2 "$IMG" 80
mkpod api     "$IMG" 80
mkpod orders  "$IMG" 80

kubectl -n "$NS" expose deploy shop-v1 --name=shop-v1 --port=80 --target-port=80 >/dev/null 2>&1
kubectl -n "$NS" expose deploy shop-v2 --name=shop-v2 --port=80 --target-port=80 >/dev/null 2>&1
# api is deliberately exposed on 8080 -> 80, so the Ingress in task 2 must
# name the SERVICE port and not the container port.
kubectl -n "$NS" expose deploy api --name=api --port=8080 --target-port=80 >/dev/null 2>&1
ok "deployments and services seeded (shop-v1, shop-v2, api:8080)"

# Task 5: the classic Ingress 503. The Service selector says app=order,
# the pods are labelled app=orders, so the Service matches nothing and has
# no endpoints. Nothing about the Ingress is wrong.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Service
metadata:
  name: orders
  namespace: $NS
spec:
  selector:
    app: order
  ports:
    - port: 80
      targetPort: 80
EOF
ok "service 'orders' seeded with a selector that matches nothing (task 5)"

# ── 5. The broken Ingress (task 3) ──────────────────────────
# Three faults, all of them things people actually ship:
#   - the class named in the pre-1.18 annotation instead of ingressClassName
#   - a backend port that no Service exposes (80, where 'api' publishes 8080)
#   - pathType Exact, so /api/orders does not match
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: legacy
  namespace: $NS
  annotations:
    kubernetes.io/ingress.class: nginx-ext
spec:
  rules:
    - host: legacy.example.com
      http:
        paths:
          - path: /api
            pathType: Exact
            backend:
              service:
                name: api
                port:
                  number: 80
EOF
ok "ingress 'legacy' seeded with three faults (task 3)"

# ── 6. The orphaned HTTPRoute (task 9) ──────────────────────
if [ "$GWOK" = "1" ]; then
  kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: stale-route
  namespace: $NS
spec:
  parentRefs:
    - name: old-edge
  hostnames:
    - "orders.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /orders
      backendRefs:
        - name: orders
          port: 80
EOF
  ok "httproute 'stale-route' seeded pointing at a Gateway that does not exist (task 9)"
fi

# ── 7. The CNI DaemonSet (task 13) ──────────────────────────
# Shaped like a real CNI agent and missing the three things every real one
# has. It runs a sleep; it is not a CNI and cannot break anything.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cni-agent
  namespace: kube-system
  labels: {k8s-app: cni-agent}
spec:
  selector:
    matchLabels: {k8s-app: cni-agent}
  template:
    metadata:
      labels: {k8s-app: cni-agent}
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sleep", "86400"]
          resources:
            requests: {cpu: 10m, memory: 16Mi}
EOF
ok "daemonset 'cni-agent' seeded in kube-system, missing what a CNI needs (task 13)"

# ── 8. TLS material for task 4 ──────────────────────────────
if command -v openssl >/dev/null 2>&1; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "$EX10/shop.key" -out "$EX10/shop.crt" \
    -subj "/CN=shop.example.com/O=cka-practice" >/dev/null 2>&1 \
    && ok "self-signed cert for shop.example.com written to $EX10/shop.{crt,key}" \
    || warn "openssl failed — task 4 expects $EX10/shop.crt and shop.key"
else
  warn "no openssl: task 4 needs a cert and key at $EX10/shop.{crt,key}"
fi

# ── 9. Wait for the backends, THEN break the network ────────
# Order matters. Existing pods keep their sandboxes when the CNI config goes
# away; only NEW pods fail. So everything must be running first, or the exam
# starts with four pods stuck in ContainerCreating for the wrong reason.
say "waiting for the backends to start before breaking anything..."
for d in shop-v1 shop-v2 api orders; do
  kubectl -n "$NS" rollout status deploy/"$d" --timeout=90s >/dev/null 2>&1
done
READY="$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -c ' Running ')"
[ "${READY:-0}" -ge 1 ] && ok "$READY backend pods Running" \
  || warn "no backend pods reached Running — the cluster may be slow; the object-graded tasks still work"

BK="/root/.cka-exam10-backup"
say "disabling the CNI configuration on '$NODE'..."
onnode "
  set -e
  mkdir -p $BK
  [ -d $BK/net.d ] || cp -a $CNIDIR $BK/net.d
  # An unmatched glob stays literal, so the -f test legitimately fails and,
  # under 'set -e', would abort the whole remote script before the fault is
  # planted. Hence the '|| true'.
  for f in $CNIDIR/*.conf $CNIDIR/*.conflist $CNIDIR/*.json; do
    { [ -f \"\$f\" ] && mv \"\$f\" \"\$f.disabled\"; } || true
  done
  # An invalid config that sorts FIRST. The runtime reads the directory in
  # lexical order, so this is the file it complains about, and it is the
  # reason a candidate who restores the real one still sees errors in the log
  # until they remove it.
  printf '%s\n' '{ \"cniVersion\": \"1.0.0\", \"name\": \"broken\", \"plugins\": [ { \"type\": ] }' \
    > $CNIDIR/00-broken.conflist
  systemctl restart containerd 2>/dev/null || systemctl restart crio 2>/dev/null || true
" || die "could not modify $CNIDIR on '$NODE'"

planted=0
onnode "[ -f $CNIDIR/00-broken.conflist ]" && planted=$((planted+1)) \
  || warn "the invalid config was not planted"
onnode "ls $CNIDIR/*.conflist.disabled $CNIDIR/*.conf.disabled >/dev/null 2>&1" && planted=$((planted+1)) \
  || warn "nothing was disabled — did this node have a CNI config at all?"
ok "$planted of 2 CNI faults planted (backup at $NODE:$BK)"

say "waiting for the node to report the network as unavailable (~60s)..."
for i in $(seq 1 25); do
  st="$(kubectl get node "$NODE" --no-headers 2>/dev/null | awk '{print $2}')"
  case "$st" in *NotReady*) break ;; esac
  sleep 3
done
st="$(kubectl get node "$NODE" --no-headers 2>/dev/null | awk '{print $2}')"
case "$st" in
  *NotReady*) ok "'$NODE' is now $st — as intended" ;;
  *) warn "'$NODE' still reports '$st'. Some runtimes cache the last good CNI
      config until they are restarted; give it another minute, or run
      'ssh $NODE systemctl restart containerd'." ;;
esac

# ── 10. Notes and the restore script ────────────────────────
cat > "$EX10/README.txt" <<EOF
Exam 10 — Ingress, Gateway API, and the CNI

Namespace: $NS      Broken node: $NODE

WHAT IS SEEDED

  deploy/svc shop-v1, shop-v2   two versions to split traffic between
  deploy/svc api                published on port 8080, container port 80
  deploy    orders              labelled app=orders
  svc       orders              selector app=order — matches nothing (task 5)
  ingress   legacy              three faults (task 3)
  httproute stale-route         parented to a Gateway that does not exist (task 9)
  ds/cni-agent (kube-system)    shaped like a CNI agent, missing what one needs (task 13)

  $EX10/shop.crt, shop.key      for the TLS task

WHAT WAS DONE TO $NODE

  - every file in $CNIDIR renamed to *.disabled
  - $CNIDIR/00-broken.conflist planted, containing invalid JSON
  - the container runtime restarted, so it re-read the directory

  Pristine copies:  $NODE:$BK/net.d

  Existing pods keep running — their network namespaces were already set up.
  It is NEW pods that cannot be created, which is exactly how this fault
  presents in production.

NO CONTROLLER IS INSTALLED, ON PURPOSE

  There is no ingress-nginx and no Gateway implementation. Ingresses will not
  get an ADDRESS and Gateways will not become Accepted or Programmed. Every
  task is graded on the object you wrote, which is also how the CKA grades
  them. Do not chase a missing address.

USEFUL COMMANDS

  kubectl -n $NS get ingress,svc,endpointslice
  kubectl -n $NS describe ingress legacy
  kubectl get gatewayclass,gateway -A
  kubectl -n $NS get httproute stale-route -o yaml

  ssh $NODE
  ls -l $CNIDIR
  journalctl -u kubelet -n 40 --no-pager | grep -i cni
  crictl info | head -20

PUT EVERYTHING BACK

  exam10restore                 (or ./exam10.sh restore)

Answer files go in $ANS
EOF

cat > "$EX10/restore.sh" <<EOF
#!/usr/bin/env bash
# Restores '$NODE' to the state it was in before setup10.sh ran.
set -uo pipefail
NODE="$NODE"
BK="$BK"
CNIDIR="$CNIDIR"
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
echo
echo "  restoring the CNI configuration on \$NODE from \$BK ..."
\$SSH "\$NODE" "
  rm -f \$CNIDIR/00-broken.conflist
  for f in \$CNIDIR/*.disabled; do
    [ -f \"\\\$f\" ] && mv -f \"\\\$f\" \"\\\${f%.disabled}\"
  done
  [ -d \$BK/net.d ] && cp -an \$BK/net.d/. \$CNIDIR/ 2>/dev/null
  systemctl restart containerd 2>/dev/null || systemctl restart crio 2>/dev/null || true
" || { echo "  could not restore over ssh"; exit 1; }
kubectl delete ns $NS --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete ingressclass nginx-ext --ignore-not-found >/dev/null 2>&1
kubectl delete gatewayclass edge-class --ignore-not-found >/dev/null 2>&1
kubectl -n kube-system delete ds cni-agent --ignore-not-found >/dev/null 2>&1
echo "  waiting for \$NODE to go Ready ..."
for i in \$(seq 1 40); do
  s="\$(kubectl get node "\$NODE" --no-headers 2>/dev/null | awk '{print \$2}')"
  [ "\$s" = "Ready" ] && { echo "  \$NODE is Ready"; exit 0; }
  sleep 3
done
echo "  \$NODE is still not Ready — check 'ssh \$NODE journalctl -u kubelet -n 50'"
EOF
chmod +x "$EX10/restore.sh"
ok "notes in $EX10/README.txt, restore script in $EX10/restore.sh"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_LINE="source ${HERE}/activate.sh"
if [ -f "${HERE}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-helm-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

echo
printf "%s  Done.%s Load the commands into this shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "  Then, from any directory:\n\n"
printf "    %scka use gateway%s   %s# select this exam%s\n" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s\n\n" "$BO" "$N" "$D" "$N"
printf "  %sStart with 'kubectl -n %s get ingress,svc' and 'kubectl get nodes'.%s\n" "$D" "$NS" "$N"
printf "  %sIf the Killercoda session expires, run %s/setup10.sh again.%s\n\n" "$D" "$HERE" "$N"
