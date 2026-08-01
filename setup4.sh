#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · setup4.sh
#  Seeds the FOURTH exam: NetworkPolicy and network
#  troubleshooting.
#
#  No Helm and no chart repositories — this one is pure
#  kubectl. It needs container images (nginx:alpine and
#  busybox), so it needs egress to a registry, but nothing else
#  from the internet.
#
#  It uses its own namespaces (frontend, backend, monitoring,
#  shop, netdebug) and its own answer directory (~/answers4),
#  so it coexists with the three Helm exams.
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers4"
EX4="$BASE/exam4"
SRV_IMAGE="${CKA_NP_SRV_IMAGE:-nginx:alpine}"
CLI_IMAGE="${CKA_NP_CLI_IMAGE:-busybox:1.36}"
NS_LIST="frontend backend monitoring shop netdebug"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
say(){ printf "  %s\n" "$*"; }
ok(){ printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){ printf "  ${R}✘${N} %s\n" "$*"; exit 1; }

echo
printf "%s  Preparing exam 4%s %s(NetworkPolicy + network troubleshooting)%s\n\n" "$BO" "$N" "$D" "$N"

# ── 1. Requirements ─────────────────────────────────────────
command -v kubectl >/dev/null || die "no kubectl found: run this on a node with a cluster (Killercoda, kind, minikube)"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable ($(kubectl version -o json 2>/dev/null | tr ',' '\n' | grep -m1 gitVersion | cut -d'"' -f4 || echo '?'))"

mkdir -p "$ANS" "$EX4"

# ── 2. Clean slate ──────────────────────────────────────────
for ns in $NS_LIST np-probe; do
  kubectl delete ns "$ns" --ignore-not-found --wait=false >/dev/null 2>&1
done
# Namespaces terminate asynchronously; creating one while it is Terminating
# fails, so wait for them to actually go.
for i in $(seq 1 30); do
  still="$(kubectl get ns $NS_LIST np-probe 2>/dev/null | grep -c . || true)"
  [ "${still:-0}" -eq 0 ] && break
  sleep 2
done
rm -rf "$ANS" "$EX4"; mkdir -p "$ANS" "$EX4"
ok "previous state removed"

# ── 3. Namespaces, with the labels the tasks select on ──────
# NetworkPolicy has no way to name a namespace: namespaceSelector matches
# LABELS. That is why every namespace here carries one.
kubectl create ns frontend  >/dev/null 2>&1
kubectl create ns backend   >/dev/null 2>&1
kubectl create ns monitoring >/dev/null 2>&1
kubectl create ns shop      >/dev/null 2>&1
kubectl create ns netdebug  >/dev/null 2>&1
kubectl label ns frontend   tier=frontend --overwrite >/dev/null 2>&1
kubectl label ns backend    tier=backend --overwrite >/dev/null 2>&1
kubectl label ns monitoring purpose=monitoring --overwrite >/dev/null 2>&1
kubectl label ns shop       tier=shop --overwrite >/dev/null 2>&1
ok "namespaces created and labelled"

mkpod(){ # name ns image labels [args...]
  local name="$1" ns="$2" img="$3" labels="$4"; shift 4
  kubectl -n "$ns" run "$name" --image="$img" --labels="$labels" \
    --restart=Never "$@" >/dev/null 2>&1
}

say "creating workloads (images may need pulling, ~60s)..."

# Servers listen on 80; clients just sleep so we can exec into them.
mkpod web    frontend "$SRV_IMAGE" "app=web,tier=frontend" --port=80
mkpod client frontend "$CLI_IMAGE" "app=client" -- sleep 86400
mkpod api    backend  "$SRV_IMAGE" "app=api,tier=backend" --port=80
mkpod db     backend  "$SRV_IMAGE" "app=db,tier=backend" --port=80
mkpod prom   monitoring "$CLI_IMAGE" "app=prom" -- sleep 86400
mkpod tester netdebug "$CLI_IMAGE" "app=tester" -- sleep 86400

# ── 4. The 'shop' namespace: three broken Services ──────────
kubectl -n shop create deployment store --image="$SRV_IMAGE" --replicas=3 >/dev/null 2>&1
kubectl -n shop patch deployment store --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/ports","value":[{"containerPort":80}]}]' >/dev/null 2>&1

# Task 9: selector says app=stores, the pods are app=store. No endpoints.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: store
  namespace: shop
spec:
  selector:
    app: stores
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF

# Task 10: selector is right, so endpoints exist, but targetPort 8080 is not
# where nginx listens. Connections are refused, which looks identical to a
# selector problem until you check endpoints.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: checkout
  namespace: shop
spec:
  selector:
    app: store
  ports:
    - name: http
      port: 80
      targetPort: 8080
EOF

# Task 12: exists as ClusterIP, has to become a NodePort on a fixed port.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: store-np
  namespace: shop
spec:
  type: ClusterIP
  selector:
    app: store
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF
ok "namespace 'shop' seeded with three broken Services"

# Task 11: a pod that cannot resolve anything, because dnsPolicy None points
# it at a nameserver that does not exist.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: dnsbroken
  namespace: shop
  labels:
    app: dnsbroken
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers:
      - 203.0.113.53
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "86400"]
EOF
ok "pod 'dnsbroken' seeded with a broken DNS configuration"

# ── 5. Task 8: a policy that looks right and matches nothing ─
# 'clientt' is a typo. The policy selects app=web, so web is isolated, and
# the only allow rule matches no pod — so nothing can reach web at all.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-web
  namespace: frontend
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: clientt
      ports:
        - protocol: TCP
          port: 80
EOF
ok "policy 'allow-client-to-web' seeded with a planted fault"

# ── 6. Task 13: three policies selecting different pods ─────
# Only some of these apply to pod 'db'. Working out which is the task.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-tier-lock
  namespace: backend
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-only
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: web
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-direct
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: api
EOF
ok "three policies seeded in 'backend' for the inventory task"

# ── 7. Wait for the pods that tasks exec into ───────────────
say "waiting for pods to be Ready..."
for spec in "web frontend" "client frontend" "api backend" "db backend" \
            "prom monitoring" "tester netdebug"; do
  set -- $spec
  kubectl -n "$2" wait --for=condition=Ready "pod/$1" --timeout=90s >/dev/null 2>&1 \
    || warn "pod $1 in $2 is not Ready yet — it may still be pulling"
done
kubectl -n shop rollout status deploy/store --timeout=90s >/dev/null 2>&1 \
  || warn "deployment store is not ready yet"
ok "workloads up"

# ── 8. Does this CNI actually ENFORCE NetworkPolicy? ────────
# This matters more than anything else in this exam. Flannel, and any
# cluster with no policy controller, accepts NetworkPolicy objects and
# silently ignores them: kubectl apply succeeds, the object is stored, and
# no traffic is ever blocked. Rather than guess from the CNI name, probe it.
probe_enforcement(){
  kubectl create ns np-probe >/dev/null 2>&1
  kubectl -n np-probe run psrv --image="$SRV_IMAGE" --labels=role=psrv \
    --restart=Never --port=80 >/dev/null 2>&1
  kubectl -n np-probe run pcli --image="$CLI_IMAGE" --labels=role=pcli \
    --restart=Never -- sleep 600 >/dev/null 2>&1
  kubectl -n np-probe wait --for=condition=Ready pod/psrv --timeout=90s >/dev/null 2>&1 || return 2
  kubectl -n np-probe wait --for=condition=Ready pod/pcli --timeout=90s >/dev/null 2>&1 || return 2

  local ip; ip="$(kubectl -n np-probe get pod psrv -o jsonpath='{.status.podIP}' 2>/dev/null)"
  [ -n "$ip" ] || return 2

  # Baseline: with no policy at all this must succeed, otherwise the probe
  # itself is broken and tells us nothing.
  kubectl -n np-probe exec pcli -- wget -q -T4 -O- "http://$ip" >/dev/null 2>&1 || return 2

  kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: probe-deny
  namespace: np-probe
spec:
  podSelector: {}
  policyTypes:
    - Ingress
EOF
  sleep 5
  # Now it must FAIL. If it still succeeds, nothing is enforcing.
  if kubectl -n np-probe exec pcli -- wget -q -T4 -O- "http://$ip" >/dev/null 2>&1; then
    return 1   # not enforced
  fi
  return 0     # enforced
}

say "checking whether the CNI enforces NetworkPolicy (~30s)..."
probe_enforcement; PROBE=$?
kubectl delete ns np-probe --ignore-not-found --wait=false >/dev/null 2>&1

case "$PROBE" in
  0) echo "enforced" > "$EX4/enforcement"
     ok "NetworkPolicy is ENFORCED — connectivity tests will behave for real" ;;
  1) echo "not-enforced" > "$EX4/enforcement"
     warn "NetworkPolicy is NOT enforced by this cluster's CNI."
     say "   ${D}Objects will apply fine and block nothing. Grading reads the${N}"
     say "   ${D}policy you wrote, so the exam still works — but 'netcheck' will${N}"
     say "   ${D}not show traffic being denied. For real enforcement use a${N}"
     say "   ${D}cluster with Calico or Cilium.${N}" ;;
  *) echo "unknown" > "$EX4/enforcement"
     warn "could not determine whether NetworkPolicy is enforced (probe failed)" ;;
esac

# ── 9. Reference notes ──────────────────────────────────────
cat > "$EX4/README.txt" <<EOF
Exam 4 — NetworkPolicy and network troubleshooting

The cluster is seeded like this:

  ns frontend   (label tier=frontend)
     pod web     labels app=web,tier=frontend    serves :80
     pod client  labels app=client               busybox, exec into it to test
     netpol allow-client-to-web  <- has a planted fault (task 8)

  ns backend    (label tier=backend)
     pod api     labels app=api,tier=backend     serves :80
     pod db      labels app=db,tier=backend      serves :80
     netpol db-tier-lock / api-only / db-direct  (task 13)

  ns monitoring (label purpose=monitoring)
     pod prom    labels app=prom                 busybox

  ns shop       (label tier=shop)
     deploy store (3 replicas, app=store)        serves :80
     svc store     <- broken selector  (task 9)
     svc checkout  <- broken targetPort (task 10)
     svc store-np  <- ClusterIP, must become NodePort (task 12)
     pod dnsbroken <- broken dnsPolicy (task 11)

  ns netdebug
     pod tester  labels app=tester               busybox

Testing connectivity by hand:

  kubectl -n frontend exec client -- wget -q -T3 -O- http://<ip-or-svc>
  kubectl -n shop get endpoints
  kubectl -n shop exec dnsbroken -- nslookup store.shop.svc.cluster.local

Files you are asked to produce go in $ANS
EOF
ok "notes written to $EX4/README.txt"

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
printf "    %scka use netpol%s   %s# select this exam%s
" "$BO" "$N" "$D" "$N"
printf "    %sq 1 · next · grade · explain 1 · info%s  %s# then work on it%s

" "$BO" "$N" "$D" "$N"
printf "  %sThe Helm exams stay available alongside it.%s\n" "$D" "$N"
printf "  %sIf the Killercoda session expires, run %s/setup4.sh again.%s\n\n" "$D" "$HERE" "$N"
