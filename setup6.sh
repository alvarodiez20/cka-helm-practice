#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · setup6.sh
#  Seeds the SIXTH exam: general cluster troubleshooting.
#
#  Troubleshooting is 30% of the CKA — the highest-weighted
#  domain. Exam 4 covers networking, exam 5 covers worker
#  nodes; this one covers the rest: the control plane, the pod
#  lifecycle, RBAC, storage, quotas and events.
#
#  It breaks kube-scheduler on purpose (by pointing its static
#  pod manifest at a kubeconfig that does not exist). That is
#  safe: the API server and etcd are untouched, so kubectl —
#  and therefore grading — keeps working. It deliberately does
#  NOT break kube-apiserver or etcd, which would take the
#  cluster and the grader down with them.
#
#  The manifest is backed up first and 'exam6restore' puts it
#  back.
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers6"
EX6="$BASE/exam6"
NS="tshoot"
SRV_IMAGE="${CKA_T6_IMAGE:-nginx:alpine}"
BUSY="${CKA_T6_BUSY:-busybox:1.36}"
MANIFEST="/etc/kubernetes/manifests/kube-scheduler.yaml"
BK="/root/.cka-exam6-backup"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
say(){ printf "  %s\n" "$*"; }
ok(){ printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){ printf "  ${R}✘${N} %s\n" "$*"; exit 1; }

echo
printf "%s  Preparing exam 6%s %s(general cluster troubleshooting)%s\n\n" "$BO" "$N" "$D" "$N"
printf "  %sThis stops kube-scheduler on purpose. The API server and etcd are%s\n" "$Y" "$N"
printf "  %sleft alone, so kubectl keeps working. 'exam6restore' undoes it.%s\n\n" "$Y" "$N"

command -v kubectl >/dev/null || die "no kubectl found"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

# The scheduler manifest lives on the control plane node. Usually that is
# this machine; if not, we still run every workload task and skip task 1.
HAVE_MANIFEST=0
if [ -f "$MANIFEST" ]; then
  HAVE_MANIFEST=1
  ok "found $MANIFEST — the scheduler task is available"
else
  warn "no $MANIFEST here."
  say "   ${D}Run this on the control plane node to get task 1. Everything else${N}"
  say "   ${D}works from anywhere with kubectl.${N}"
fi

mkdir -p "$ANS" "$EX6"

# ── 1. Clean slate ──────────────────────────────────────────
kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1
for i in $(seq 1 25); do kubectl get ns "$NS" >/dev/null 2>&1 || break; sleep 2; done
kubectl delete pod sched-canary --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete pv tshoot-pv --ignore-not-found >/dev/null 2>&1
kubectl delete clusterrolebinding tshoot-reader --ignore-not-found >/dev/null 2>&1
rm -rf "$ANS" "$EX6"; mkdir -p "$ANS" "$EX6"
kubectl create ns "$NS" >/dev/null 2>&1
ok "namespace '$NS' created fresh"

# ── 2. Broken workloads ─────────────────────────────────────
# These must be SCHEDULED before the scheduler is broken, otherwise they sit
# Pending and show none of the symptoms the tasks are about.

# Task 2: OOMKilled. A 4Mi limit is below what nginx needs to start, so the
# kernel kills it immediately and the container reports exit code 137.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: hungry, namespace: $NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: hungry}}
  template:
    metadata: {labels: {app: hungry}}
    spec:
      containers:
        - name: c
          image: $SRV_IMAGE
          resources:
            requests: {cpu: 10m, memory: 4Mi}
            limits:   {cpu: 100m, memory: 4Mi}
EOF

# Task 4: ImagePullBackOff — a tag that does not exist.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: badimage, namespace: $NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: badimage}}
  template:
    metadata: {labels: {app: badimage}}
    spec:
      containers:
        - name: c
          image: nginx:1.99-does-not-exist
          resources: {requests: {cpu: 10m, memory: 16Mi}}
EOF

# Task 5: CreateContainerConfigError — envFrom names a ConfigMap that is not
# there. The pod never starts, and the reason is NOT in the logs.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: needs-config, namespace: $NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: needs-config}}
  template:
    metadata: {labels: {app: needs-config}}
    spec:
      containers:
        - name: c
          image: $SRV_IMAGE
          envFrom:
            - configMapRef: {name: app-settings}
          resources: {requests: {cpu: 10m, memory: 16Mi}}
EOF

# Task 6: a liveness probe pointing at a port nothing listens on, so the
# kubelet keeps killing a container that is perfectly healthy.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: probed, namespace: $NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: probed}}
  template:
    metadata: {labels: {app: probed}}
    spec:
      containers:
        - name: c
          image: $SRV_IMAGE
          ports: [{containerPort: 80}]
          livenessProbe:
            httpGet: {path: /, port: 8080}
            initialDelaySeconds: 3
            periodSeconds: 5
          resources: {requests: {cpu: 10m, memory: 16Mi}}
EOF

# Task 7: an init container that never succeeds, so the app container never
# starts. 'kubectl logs' on the pod shows nothing useful until you name the
# init container.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: initstuck, namespace: $NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: initstuck}}
  template:
    metadata: {labels: {app: initstuck}}
    spec:
      initContainers:
        - name: wait-for-it
          image: $BUSY
          command: ["sh","-c","test -f /shared/ready"]
      containers:
        - name: c
          image: $SRV_IMAGE
          resources: {requests: {cpu: 10m, memory: 16Mi}}
EOF

# Task 3: a container that exits non-zero once, so there is a --previous log
# to read and a real exit code to report.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: {name: exiter, namespace: $NS, labels: {app: exiter}}
spec:
  containers:
    - name: c
      image: $BUSY
      command: ["sh","-c","echo 'FATAL: config missing, giving up' >&2; exit 3"]
      resources: {requests: {cpu: 10m, memory: 16Mi}}
EOF
ok "broken workloads created in '$NS'"

# ── 3. RBAC, storage and quota ──────────────────────────────
kubectl -n "$NS" create serviceaccount inspector >/dev/null 2>&1

# Task 9: a PVC that cannot bind — it asks for a storage class that has no
# PV and no provisioner behind it.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: PersistentVolume
metadata: {name: tshoot-pv}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: slow
  hostPath: {path: /tmp/tshoot-pv}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data, namespace: $NS}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast
  resources: {requests: {storage: 1Gi}}
EOF

# Task 10: a quota tight enough that the next replica is refused.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: ResourceQuota
metadata: {name: tight, namespace: $NS}
spec:
  hard:
    pods: "8"
    requests.cpu: "500m"
EOF

# Task 13: an object wedged in Terminating by a finalizer nobody will clear.
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: stuck-cm
  namespace: $NS
  finalizers: ["example.com/keep-me"]
data: {note: "deleting this needs the finalizer removed first"}
EOF
kubectl -n "$NS" delete configmap stuck-cm --wait=false >/dev/null 2>&1
ok "RBAC, PV/PVC, quota and a finalizer-wedged ConfigMap seeded"

say "waiting for the broken pods to reach their broken states (~60s)..."
sleep 25
for i in $(seq 1 12); do
  bad="$(kubectl -n "$NS" get pods --no-headers 2>/dev/null \
        | grep -cE 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|Init:|Error' || true)"
  [ "${bad:-0}" -ge 4 ] && break
  sleep 5
done
ok "workloads are showing their symptoms"

# ── 4. Break kube-scheduler, last ───────────────────────────
# Last, so that everything above got scheduled first. Once the scheduler is
# down nothing NEW can be placed — which is exactly the lesson, and the
# reason task 1 has to be solved before any other fix takes effect.
if [ "$HAVE_MANIFEST" = "1" ]; then
  mkdir -p "$BK"
  [ -f "$BK/kube-scheduler.yaml" ] || cp -a "$MANIFEST" "$BK/kube-scheduler.yaml"

  # Point --kubeconfig at a file that does not exist. The container then
  # crashloops with an unambiguous error, and the fix is self-evident from
  # an 'ls /etc/kubernetes/'.
  sed -i 's#--kubeconfig=/etc/kubernetes/scheduler.conf#--kubeconfig=/etc/kubernetes/scheduler-WRONG.conf#' "$MANIFEST"

  if grep -q 'scheduler-WRONG.conf' "$MANIFEST"; then
    ok "kube-scheduler manifest broken (backup in $BK)"
  else
    warn "could not plant the scheduler fault — unexpected manifest layout"
  fi

  say "waiting for the scheduler to go down (~30s)..."
  for i in $(seq 1 15); do
    kubectl -n kube-system get pods -l component=kube-scheduler --no-headers 2>/dev/null \
      | grep -qE 'Running.*\s1/1' || break
    sleep 3
  done

  # A canary that cannot be placed until the scheduler is back. Grading task
  # 1 on this is a behavioural check, not a "does the pod look Running" one.
  kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: {name: sched-canary, labels: {app: sched-canary}}
spec:
  containers:
    - name: c
      image: $BUSY
      command: ["sleep","86400"]
      resources: {requests: {cpu: 10m, memory: 16Mi}}
EOF
  sleep 5
  if [ -z "$(kubectl get pod sched-canary -o jsonpath='{.spec.nodeName}' 2>/dev/null)" ]; then
    ok "canary pod 'sched-canary' is unschedulable — the scheduler is down"
  else
    warn "the canary was scheduled anyway; the scheduler may still be up"
  fi
fi

# ── 5. Notes + restore ──────────────────────────────────────
cat > "$EX6/README.txt" <<EOF
Exam 6 — general cluster troubleshooting

Namespace: $NS

What is wrong, so you can check your own diagnosis afterwards:

  kube-scheduler        static pod manifest points --kubeconfig at
                        /etc/kubernetes/scheduler-WRONG.conf
  pod/sched-canary      cannot be placed until the scheduler is back
  deploy/hungry         memory limit 4Mi, so it is OOMKilled (exit 137)
  deploy/badimage       image tag nginx:1.99-does-not-exist
  deploy/needs-config   envFrom a ConfigMap 'app-settings' that does not exist
  deploy/probed         livenessProbe on port 8080; nginx listens on 80
  deploy/initstuck      init container waits for a file that never appears
  pod/exiter            exits 3 with a message on stderr
  pvc/data              wants storageClassName 'fast'; the PV offers 'slow'
  resourcequota/tight   500m CPU total, 8 pods
  configmap/stuck-cm    deleted, but wedged by finalizer example.com/keep-me
  sa/inspector          has no permissions at all

Nothing you fix will actually START until the scheduler is running again,
because new pods cannot be placed. Do task 1 first.

The commands this exam is really about:

  kubectl describe pod <p> -n $NS        the Events section is 80% of it
  kubectl logs <p> -n $NS --previous     logs from before the last crash
  kubectl logs <p> -n $NS -c <container> a specific (or init) container
  kubectl get events -n $NS --sort-by=.lastTimestamp
  kubectl -n kube-system logs kube-scheduler-\$(hostname)
  kubectl auth can-i <verb> <resource> --as=system:serviceaccount:$NS:inspector

Answer files go in $ANS
EOF

cat > "$EX6/restore.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
echo
if [ -f "$BK/kube-scheduler.yaml" ]; then
  cp -a "$BK/kube-scheduler.yaml" "$MANIFEST"
  echo "  kube-scheduler manifest restored; waiting for it to come back..."
  for i in \$(seq 1 30); do
    kubectl -n kube-system get pods -l component=kube-scheduler --no-headers 2>/dev/null \
      | grep -q 'Running' && { echo "  kube-scheduler is Running"; break; }
    sleep 3
  done
else
  echo "  no scheduler backup found — nothing to restore"
fi
kubectl -n $NS patch configmap stuck-cm --type=merge \
  -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
kubectl delete ns $NS --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete pod sched-canary --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete pv tshoot-pv --ignore-not-found >/dev/null 2>&1
echo "  exam 6 objects removed"
EOF
chmod +x "$EX6/restore.sh"
ok "notes in $EX6/README.txt, restore script in $EX6/restore.sh"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_LINE="source ${HERE}/activate.sh"
if [ -f "${HERE}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-helm-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

echo
printf "%s  Done.%s Load the commands into this shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "    exam6          %s# list the 13 tasks%s\n" "$D" "$N"
printf "    q6 1           %s# read a task%s\n" "$D" "$N"
printf "    grade6         %s# grade and see your score out of 100%s\n" "$D" "$N"
printf "    explain6 1     %s# step-by-step walkthrough%s\n" "$D" "$N"
printf "    triage         %s# every unhealthy object, in one screen%s\n" "$D" "$N"
printf "    exam6restore   %s# undo everything%s\n\n" "$D" "$N"
printf "  %sStart with task 1: nothing else will start while the scheduler is down.%s\n\n" "$Y" "$N"
