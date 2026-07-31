#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · setup7.sh
#  Seeds the SEVENTH exam: storage.
#
#  Storage is 10% of the CKA and is the domain this suite had
#  almost nothing on. Everything here is static PVs and local
#  paths, so it works on any cluster — no dynamic provisioner
#  required, and nothing destructive.
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers7"
EX7="$BASE/exam7"
NS="store-lab"
SRV_IMAGE="${CKA_S7_IMAGE:-nginx:alpine}"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
say(){ printf "  %s\n" "$*"; }
ok(){ printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){ printf "  ${R}✘${N} %s\n" "$*"; exit 1; }

echo
printf "%s  Preparing exam 7%s %s(storage)%s\n\n" "$BO" "$N" "$D" "$N"

command -v kubectl >/dev/null || die "no kubectl found"
kubectl get nodes >/dev/null 2>&1 || die "kubectl cannot reach any cluster"
ok "cluster reachable"

mkdir -p "$ANS" "$EX7"

# ── Clean slate ─────────────────────────────────────────────
kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1
for i in $(seq 1 25); do kubectl get ns "$NS" >/dev/null 2>&1 || break; sleep 2; done
for pv in pv-small pv-recycled pv-sts-0 pv-sts-1; do
  kubectl patch pv "$pv" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
  kubectl delete pv "$pv" --ignore-not-found --wait=false >/dev/null 2>&1
done
kubectl delete storageclass slow-local fast-local --ignore-not-found >/dev/null 2>&1
rm -rf "$ANS" "$EX7"; mkdir -p "$ANS" "$EX7"
sleep 3
kubectl create ns "$NS" >/dev/null 2>&1
ok "namespace '$NS' created fresh"

# ── Task 2: a PV that a claim will fail to match on SIZE ────
# The claim asks for 5Gi and this offers 2Gi. Everything else lines up,
# which is what makes it worth diagnosing rather than guessing.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: {name: pv-small}
spec:
  capacity: {storage: 2Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath: {path: /mnt/pv-small}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: too-big, namespace: store-lab}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources: {requests: {storage: 5Gi}}
EOF

# ── Task 3: the Released trap ───────────────────────────────
# A Retain PV whose claim has been deleted goes to Released and will NOT
# rebind to anything, ever, until .spec.claimRef is cleared. It looks
# available and behaves as though it is not, which is the whole lesson.
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: {name: pv-recycled}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: archive
  hostPath: {path: /mnt/pv-recycled}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: temp-claim, namespace: store-lab}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: archive
  resources: {requests: {storage: 1Gi}}
EOF

say "binding then releasing a PV to reach the Released state (~20s)..."
for i in $(seq 1 15); do
  [ "$(kubectl get pv pv-recycled -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && break
  sleep 2
done
kubectl -n "$NS" delete pvc temp-claim --wait=false >/dev/null 2>&1
sleep 5
phase="$(kubectl get pv pv-recycled -o jsonpath='{.status.phase}' 2>/dev/null)"
if [ "$phase" = "Released" ]; then
  ok "pv-recycled is Released — it will not rebind until claimRef is cleared"
else
  warn "pv-recycled is '$phase' rather than Released; task 3 may look different"
fi

# ── Tasks 11: static PVs for the StatefulSet ────────────────
# A StatefulSet's volumeClaimTemplates need one PV per replica, and they
# bind by ordinal, so two are provided.
for i in 0 1; do
  kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: PersistentVolume
metadata: {name: pv-sts-$i}
spec:
  capacity: {storage: 512Mi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Delete
  storageClassName: sts-local
  hostPath: {path: /mnt/pv-sts-$i}
EOF
done
ok "two PVs seeded for the StatefulSet task"

# ── Task 10: a ConfigMap to mount with subPath ──────────────
kubectl -n "$NS" create configmap site-config \
  --from-literal=index.html='<h1>from the configmap</h1>' \
  --from-literal=notes.txt='not mounted' >/dev/null 2>&1

# ── Task 13: a PVC held open by a running pod ───────────────
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: inuse, namespace: $NS}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: PersistentVolume
metadata: {name: pv-inuse}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath: {path: /mnt/pv-inuse}
---
apiVersion: v1
kind: Pod
metadata: {name: holder, namespace: $NS, labels: {app: holder}}
spec:
  containers:
    - name: c
      image: $SRV_IMAGE
      volumeMounts: [{name: v, mountPath: /data}]
      resources: {requests: {cpu: 10m, memory: 16Mi}}
  volumes:
    - name: v
      persistentVolumeClaim: {claimName: inuse}
EOF
sleep 4
kubectl -n "$NS" delete pvc inuse --wait=false >/dev/null 2>&1
sleep 3
ok "pvc 'inuse' deleted but held open by pod 'holder' (pvc-protection)"

cat > "$EX7/README.txt" <<EOF
Exam 7 — storage

Namespace: $NS

What is here:

  pv/pv-small       2Gi, RWO, class 'manual', Retain
  pvc/too-big       asks for 5Gi of class 'manual'  -> will not bind (task 2)
  pv/pv-recycled    1Gi, class 'archive', Retain, left in Released (task 3)
  pv/pv-sts-0/-1    512Mi each, class 'sts-local'   (task 11)
  pv/pv-inuse       1Gi, class 'manual', bound to pvc/inuse
  pvc/inuse         deleted, but pod 'holder' still mounts it (task 13)
  cm/site-config    two keys: index.html and notes.txt (task 10)

The commands this exam is about:

  kubectl get pv,pvc -n $NS
  kubectl describe pvc <name> -n $NS      the Events say WHY it will not bind
  kubectl get pv <name> -o yaml           look at claimRef, and at status.phase
  kubectl get sc

A PVC binds only when ALL of these line up:
  storageClassName equal · PV capacity >= request · accessModes offered ·
  the PV is Available (not Released) · any selector matches

Answer files go in $ANS
EOF
ok "notes written to $EX7/README.txt"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_LINE="source ${HERE}/activate.sh"
if [ -f "${HERE}/activate.sh" ] && ! grep -qF "$SRC_LINE" "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# cka-helm-practice\n%s\n' "$SRC_LINE" >> "${HOME}/.bashrc"
  ok "exam commands added to ~/.bashrc"
fi

echo
printf "%s  Done.%s Load the commands into this shell:\n\n" "$G$BO" "$N"
printf "    %s\n\n" "$SRC_LINE"
printf "    exam7          %s# list the 13 tasks%s\n" "$D" "$N"
printf "    q7 1 · grade7 · explain7 1 · storeinfo%s\n\n" "$D$N"
printf "  %sEverything here is static PVs, so no dynamic provisioner is needed.%s\n\n" "$D" "$N"
