#!/usr/bin/env bash
# ============================================================
#  cka-practice · exam7.sh
#  13 CKA-style storage tasks. 100 points. Pass mark: 66.
#
#  Storage is 10% of the CKA. Everything here uses static PVs,
#  so it works without a dynamic provisioner.
#
#    ./exams/exam7.sh q 4 · grade · explain 4 · storeinfo
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers7"
EX7="$BASE/exam7"
NS="store-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

if [ -n "${EXAM_HOME:-}" ]; then
  # activate.sh is loaded: the verbs are unnumbered and act on the exam
  # selected with 'cka use'. See cka.sh.
  CL="list"; CQ="q"; CG="grade"; CE="explain"; CS="solve"; CH="examhelp"
else
  CL="./exams/exam7.sh"; CQ="./exams/exam7.sh q"; CG="./exams/exam7.sh grade"
  CE="./exams/exam7.sh explain"; CS="./exams/exam7.sh solve"; CH="./exams/exam7.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

Q[1]="Create a PersistentVolume named 'pv-logs': 3Gi, access mode ReadWriteOnce,
storage class 'manual', reclaim policy Retain, backed by the host path
/mnt/pv-logs."
PTS[1]=7
SOL[1]="kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: {name: pv-logs}
spec:
  capacity: {storage: 3Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath: {path: /mnt/pv-logs}
EOF"
WALK[1]="1. A PV is cluster-scoped — no namespace. Every field in this task maps to
   one line, and it is worth being able to write this from memory:

     capacity.storage                 how much it offers
     accessModes                      a LIST, even for one mode
     persistentVolumeReclaimPolicy    what happens when the claim goes
     storageClassName                 the string a claim must match exactly
     hostPath / nfs / csi / local     the backend

2. The three access modes, and what they actually mean:

     ReadWriteOnce (RWO)   one NODE may mount it read-write. Note node, not
                           pod — several pods on the same node can share it.
     ReadOnlyMany (ROX)    many nodes, read-only
     ReadWriteMany (RWX)   many nodes, read-write. Most block storage cannot
                           do this; NFS and CephFS can.

   There is also ReadWriteOncePod, which really does mean one pod.

3. Reclaim policies, which decide what happens to the DATA:

     Retain   keep the volume and the data; the PV goes to Released and must
              be cleaned up by hand. Task 3 is about the consequence.
     Delete   delete the underlying storage with the claim. The default for
              most dynamic provisioners.
     Recycle  deprecated; do not use.

4. 'kubectl get storageclass' does not list 'manual', and that is correct.
   It is the question everyone asks at this point, so: a PV's
   storageClassName does NOT have to name a StorageClass object that exists.

     On a PV     storageClassName is a LABEL. It is one of the things a
                 claim is matched against, alongside capacity and access
                 mode. Nothing looks it up.
     On a PVC    the same string, used for matching — plus, if no PV
                 matches, the name of the StorageClass to PROVISION from.
                 Only that second use needs the object to exist.

   So 'manual' is the conventional name for a class meaning: these volumes
   are administered by hand, provision nothing. Static provisioning, which is
   what this exam is about, needs no StorageClass at all. Tasks 4 and 5 are
   where you create real StorageClass objects, for dynamic provisioning.

   Two related traps worth keeping straight. Set the field to the empty
   string and you mean 'explicitly no class': such a claim binds only to PVs
   that also have no class, and is never dynamically provisioned. Omit the
   field entirely and admission applies the DEFAULT StorageClass — on this
   cluster that is 'local-path', which would provision a brand new volume
   instead of binding the one you just made. That is why the task names a
   class rather than leaving it out.

5. Verify:

     kubectl get pv pv-logs
     # STATUS Available  CLAIM <none>  STORAGECLASS manual

hostPath is for single-node practice only — the path is on whichever node
the pod lands on, so on a real cluster the data effectively moves. 'local'
volumes are the production-grade version and require nodeAffinity."

Q[2]="The PersistentVolumeClaim 'too-big' in namespace '${NS}' is Pending and will
never bind, even though a PersistentVolume with the same storage class exists
and is Available.
Work out why, then make the claim bind to 'pv-small'. You may delete and
recreate the PVC; do not modify the PV."
PTS[2]=8
SOL[2]="kubectl -n ${NS} describe pvc too-big | tail -4
kubectl get pv pv-small    # 2Gi
kubectl -n ${NS} get pvc too-big -o jsonpath='{.spec.resources.requests.storage}'  # 5Gi
kubectl -n ${NS} delete pvc too-big
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: too-big, namespace: ${NS}}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources: {requests: {storage: 2Gi}}
EOF"
WALK[2]="1. Compare the two objects field by field. Binding is all-or-nothing across
   FIVE conditions, and the events rarely name which one failed:

     storageClassName   must be equal
     capacity           the PV must be >= the request
     accessModes        the PV must offer every mode the claim asks for
     volumeMode         Filesystem vs Block
     selector           if the claim has one, the PV's labels must match

     kubectl get pv pv-small \\
       -o custom-columns=NAME:.metadata.name,CAP:.spec.capacity.storage,\\
SC:.spec.storageClassName,MODES:.spec.accessModes,STATUS:.status.phase

     kubectl -n ${NS} get pvc too-big \\
       -o jsonpath='{.spec.storageClassName} {.spec.resources.requests.storage}{\"\\n\"}'
     # manual 5Gi

   The class matches; the size does not. 2Gi cannot satisfy a 5Gi request.

2. A claim may bind to a LARGER PV than it asks for — that is normal and it
   simply gets the whole volume — but never to a smaller one. So the fix is
   to ask for 2Gi or less.

3. Most of a PVC's spec is immutable, so recreate rather than edit:

     kubectl -n ${NS} delete pvc too-big
     # recreate with 2Gi

4. Verify both ends, because binding is recorded on both objects:

     kubectl -n ${NS} get pvc too-big     # Bound, VOLUME pv-small
     kubectl get pv pv-small              # Bound, CLAIM ${NS}/too-big

The two Pending messages worth telling apart:

     'no persistent volumes available for this claim'
        static binding: nothing matches. Compare the five fields above.
     'storageclass.storage.k8s.io \"x\" not found'
        dynamic binding: the class does not exist, so nobody will create one."

Q[3]="The PersistentVolume 'pv-recycled' shows status Released. A new claim for the
same storage class will not bind to it, however correct that claim is.
Make 'pv-recycled' usable again — it must return to Available — without
deleting or recreating it, and without losing its configuration."
PTS[3]=9
SOL[3]="kubectl get pv pv-recycled -o jsonpath='{.spec.claimRef}'
# it still points at the deleted claim
kubectl patch pv pv-recycled --type=json -p='[{\"op\":\"remove\",\"path\":\"/spec/claimRef\"}]'
kubectl get pv pv-recycled     # Available"
WALK[3]="1. This is the storage trap most worth knowing, because the PV LOOKS fine:

     kubectl get pv pv-recycled
     # STATUS Released   CLAIM store-lab/temp-claim

   Released means: the claim that owned this volume was deleted, the reclaim
   policy is Retain, so Kubernetes kept the data and will NOT hand the volume
   to anybody else. It is not available and never becomes available on its
   own. A new claim sits Pending for ever with no useful event.

2. The thing holding it is a stale reference:

     kubectl get pv pv-recycled -o jsonpath='{.spec.claimRef}'
     # {\"kind\":\"PersistentVolumeClaim\",\"name\":\"temp-claim\",...,\"uid\":\"...\"}

   The uid is the important part. It names a claim that no longer exists, so
   nothing can ever match it.

3. Clear it. A JSON patch removing the field is the precise way:

     kubectl patch pv pv-recycled --type=json \\
       -p='[{\"op\":\"remove\",\"path\":\"/spec/claimRef\"}]'

   'kubectl edit pv pv-recycled' and deleting the claimRef block does the
   same thing. The PV flips to Available within a second or two.

4. Verify:

     kubectl get pv pv-recycled     # STATUS Available   CLAIM <none>

5. What you are NOT doing, and should think about on a real cluster: the DATA
   is still there from the previous claim. Retain exists precisely so that a
   human looks at it first. Handing the volume to a new claim without wiping
   it hands the old data to the new workload.

Reclaim policy decides which of these you get:

     Retain   -> Released. Manual cleanup. This task.
     Delete   -> the PV object and the backing storage both disappear.

You can change the policy on a live PV, which is the standard way to protect
a volume you are about to detach:

     kubectl patch pv <pv> -p \\
       '{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Retain\"}}'"

Q[4]="Create a StorageClass named 'fast-local' that uses the provisioner
'kubernetes.io/no-provisioner', binds only once a pod needs it, reclaims with
Delete, and allows volumes to be expanded later."
PTS[4]=8
SOL[4]="kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: fast-local}
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF"
WALK[4]="1. Each phrase in the task is one field, and the mapping is worth knowing
   cold because the exam words it exactly like this:

     'uses the provisioner X'          provisioner: X
     'binds only once a pod needs it'  volumeBindingMode: WaitForFirstConsumer
     'reclaims with Delete'            reclaimPolicy: Delete
     'allows volumes to be expanded'   allowVolumeExpansion: true

2. volumeBindingMode is the one people skip, and it matters:

     Immediate               bind the PVC as soon as it is created. On a
                             multi-zone or multi-node cluster this can bind a
                             volume in a zone where the pod cannot run — the
                             pod is then unschedulable for ever.
     WaitForFirstConsumer    leave the PVC Pending until a pod that uses it is
                             scheduled, then bind somewhere that actually
                             works.

   WaitForFirstConsumer is why a perfectly healthy PVC sits Pending with
   'waiting for first consumer to be created before binding' — that is not a
   fault, and mistaking it for one wastes exam time.

3. 'kubernetes.io/no-provisioner' means nothing will create volumes
   automatically; it is what you use for statically provisioned local
   storage. A StorageClass with no provisioner is still useful: it is the
   label that matches claims to hand-made PVs.

4. Verify:

     kubectl get sc fast-local
     kubectl describe sc fast-local

Note allowVolumeExpansion only permits it — the CSI driver behind the class
also has to support it. With it true, growing a volume is just editing the
claim upward:

     kubectl -n ${NS} patch pvc <name> -p \\
       '{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"5Gi\"}}}}'

   Shrinking is never allowed."

Q[5]="Make the StorageClass 'fast-local' the cluster's default, so that a PVC which
names no storage class uses it."
PTS[5]=7
SOL[5]="kubectl patch storageclass fast-local -p \\
  '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
WALK[5]="1. 'Default' is not a field — it is an annotation, and the exact string
   matters:

     storageclass.kubernetes.io/is-default-class: \"true\"

   Note the value is the STRING \"true\". Annotations are always strings.

2. Set it:

     kubectl patch storageclass fast-local -p \\
       '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'

3. Verify — kubectl marks it in the listing, which is the quickest check:

     kubectl get sc
     # fast-local (default)   kubernetes.io/no-provisioner   ...

4. Two behaviours worth separating, because they look the same and are not:

     a PVC with NO storageClassName field     gets the default class
     a PVC with storageClassName: \"\"          explicitly asks for NO class,
                                              and will only bind to a PV that
                                              also has no class

   That empty-string form is how you opt out of dynamic provisioning
   entirely.

5. If TWO classes are annotated as default, the API server picks one
   arbitrarily and warns. Clearing a default is the same patch with \"false\":

     kubectl patch storageclass <other> -p \\
       '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'

Common traps: misspelling the annotation. There is no validation, so a typo
applies cleanly and does absolutely nothing."

Q[6]="In namespace '${NS}', create a PersistentVolumeClaim named 'logs' asking for
3Gi with ReadWriteOnce and storage class 'manual', then a Pod named 'writer'
running nginx:alpine that mounts it at /var/log/app.
The claim must end up Bound."
PTS[6]=9
SOL[6]="kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: logs, namespace: ${NS}}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources: {requests: {storage: 3Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: writer, namespace: ${NS}}
spec:
  containers:
    - name: c
      image: nginx:alpine
      volumeMounts:
        - {name: data, mountPath: /var/log/app}
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: logs}
EOF"
WALK[6]="1. This is the whole storage chain, and being able to write it without
   thinking is most of what the exam wants:

     PV  ── the volume that exists
      ↑
     PVC ── a request that binds to one PV
      ↑
     pod.spec.volumes[].persistentVolumeClaim.claimName
      ↑
     container.volumeMounts[].mountPath

   The two-step inside the pod is where people slip: 'volumes' names the
   claim at POD level, 'volumeMounts' puts it in a path at CONTAINER level,
   and the two are joined by the volume's 'name'. Both are required.

2. It binds to pv-logs from task 1 — 3Gi, RWO, class manual. If task 1 is not
   done this claim has nothing to bind to, which is itself a useful thing to
   observe.

3. Verify all three:

     kubectl -n ${NS} get pvc logs           # Bound   VOLUME pv-logs
     kubectl -n ${NS} get pod writer         # Running
     kubectl -n ${NS} exec writer -- df -h /var/log/app
     kubectl -n ${NS} exec writer -- touch /var/log/app/test

4. If the pod stays ContainerCreating, the mount is failing rather than the
   binding. describe tells you which:

     kubectl -n ${NS} describe pod writer | tail -10
     # FailedMount / Unable to attach or mount volumes

Useful extras on the same shape:

     readOnly: true            in volumeMounts, mount it read-only
     subPath: sub/dir          mount one subdirectory of the volume"

Q[7]="Write into ${ANS}/q7.txt the name of every PersistentVolume in the cluster
whose reclaim policy is Retain — one name per line, and nothing else."
PTS[7]=8
SOL[7]="kubectl get pv \\
  -o jsonpath='{range .items[?(@.spec.persistentVolumeReclaimPolicy==\"Retain\")]}{.metadata.name}{\"\\n\"}{end}' \\
  > ${ANS}/q7.txt"
WALK[7]="1. The listing shows the policy, so you can eyeball it — but the point of
   this task is the filter, because JSONPath filtering is what makes kubectl
   usable on a big cluster:

     kubectl get pv
     # NAME  CAPACITY  ACCESS MODES  RECLAIM POLICY  STATUS ...

2. Filter with a JSONPath predicate:

     kubectl get pv \\
       -o jsonpath='{range .items[?(@.spec.persistentVolumeReclaimPolicy==\"Retain\")]}{.metadata.name}{\"\\n\"}{end}'

   The pieces:
     {range ...}{end}    iterate
     [?(@.field==\"x\")]   filter; @ is the current item
     {\"\\n\"}              a literal newline between entries

   Mind the quoting: the value inside the filter needs double quotes, so the
   whole expression goes in single quotes in the shell.

3. The same thing with custom-columns, which is easier to read but harder to
   filter:

     kubectl get pv -o custom-columns=\\
NAME:.metadata.name,POLICY:.spec.persistentVolumeReclaimPolicy

   and the blunt version, which is perfectly acceptable under time pressure:

     kubectl get pv --no-headers | awk '\$4==\"Retain\"{print \$1}'

4. Write it and check:

     cat ${ANS}/q7.txt

Common traps: including the header line, or writing the whole table. The task
asked for names only."

Q[8]="A Pod named 'sidecar-pair' must run in '${NS}' with TWO containers that share
a scratch directory which does NOT survive the pod:
  - 'writer', image busybox:1.36, writing to /shared
  - 'reader', image busybox:1.36, reading from /shared
Both containers must stay running."
PTS[8]=8
SOL[8]="kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: sidecar-pair, namespace: ${NS}}
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: [\"sh\",\"-c\",\"while true; do date >> /shared/log; sleep 5; done\"]
      volumeMounts: [{name: scratch, mountPath: /shared}]
    - name: reader
      image: busybox:1.36
      command: [\"sh\",\"-c\",\"while true; do tail -n1 /shared/log; sleep 5; done\"]
      volumeMounts: [{name: scratch, mountPath: /shared}]
  volumes:
    - name: scratch
      emptyDir: {}
EOF"
WALK[8]="1. 'does NOT survive the pod' is the definition of emptyDir. It is created
   empty when the pod is assigned to a node, shared by every container in the
   pod, and deleted permanently when the pod is removed:

     volumes:
       - name: scratch
         emptyDir: {}

   It survives a CONTAINER restart. It does not survive the POD. That
   distinction is the one exams test.

2. Sharing is just mounting the same volume name in both containers, at
   whatever path each wants — the paths do not have to match, though here
   they do.

3. Both containers must keep running, so both need a command that does not
   exit. A busybox container with no command exits immediately and the pod
   goes to CrashLoopBackOff, which is what usually goes wrong here.

4. Verify the sharing actually works, not just that the pod is up:

     kubectl -n ${NS} get pod sidecar-pair        # 2/2 Running
     kubectl -n ${NS} logs sidecar-pair -c reader
     kubectl -n ${NS} exec sidecar-pair -c reader -- cat /shared/log

5. emptyDir has one option worth knowing, which puts it in RAM rather than on
   disk — fast, and counted against the container's memory limit:

     emptyDir:
       medium: Memory
       sizeLimit: 64Mi

The other 'shared scratch' answers and when they differ: hostPath ties you to
one node and survives the pod; a PVC persists properly; emptyDir is the right
answer whenever the data is genuinely temporary."

Q[9]="Create a StatefulSet named 'web' in '${NS}' with 2 replicas of nginx:alpine,
using a volumeClaimTemplate named 'data' that requests 512Mi of storage class
'sts-local' mounted at /usr/share/nginx/html.
It needs a headless Service named 'web' as well. Both pods must be Running."
PTS[9]=9
SOL[9]="kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: web, namespace: ${NS}}
spec:
  clusterIP: None
  selector: {app: web}
  ports: [{port: 80, name: http}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: web, namespace: ${NS}}
spec:
  serviceName: web
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
        - name: c
          image: nginx:alpine
          volumeMounts: [{name: data, mountPath: /usr/share/nginx/html}]
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: sts-local
        resources: {requests: {storage: 512Mi}}
EOF"
WALK[9]="1. A volumeClaimTemplate is what makes a StatefulSet different from a
   Deployment: every replica gets its OWN PVC, created automatically, named
   by a fixed convention:

     <template-name>-<statefulset-name>-<ordinal>
     data-web-0
     data-web-1

   Knowing that naming is worth points on its own — it is how you find a
   specific replica's volume.

2. The headless Service is mandatory and easy to forget. 'clusterIP: None'
   is what makes it headless, and 'serviceName: web' in the StatefulSet
   points at it. It gives each pod a stable DNS name:

     web-0.web.${NS}.svc.cluster.local

   Without it the pods still start, but they have no stable identity, which
   defeats the point of a StatefulSet.

3. Each PVC needs a PV to bind to — setup7.sh provides pv-sts-0 and pv-sts-1
   of class sts-local. With only one PV, web-0 would run and web-1 would sit
   Pending for ever, because StatefulSet pods are created strictly in order
   and it will not skip one.

4. Verify all three layers:

     kubectl -n ${NS} get sts web
     kubectl -n ${NS} get pods -l app=web       # web-0, web-1
     kubectl -n ${NS} get pvc                   # data-web-0, data-web-1

5. The behaviour that catches people out: deleting a StatefulSet does NOT
   delete its PVCs. That is deliberate — the data is the point — but it
   means a re-created StatefulSet picks the old volumes back up, and that
   stale PVCs accumulate:

     kubectl -n ${NS} delete sts web
     kubectl -n ${NS} get pvc          # data-web-0 and -1 are still there

   Newer clusters can change this with .spec.persistentVolumeClaimRetentionPolicy."

Q[10]="In '${NS}' there is a ConfigMap 'site-config' with two keys.
Create a Pod named 'onefile' running nginx:alpine that mounts ONLY the
'index.html' key, as the file /usr/share/nginx/html/index.html, leaving the
rest of that directory intact."
PTS[10]=8
SOL[10]="kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: onefile, namespace: ${NS}}
spec:
  containers:
    - name: c
      image: nginx:alpine
      volumeMounts:
        - name: cfg
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
  volumes:
    - name: cfg
      configMap:
        name: site-config
EOF"
WALK[10]="1. The problem this solves: mounting a volume at a directory REPLACES that
   directory. Mount site-config at /usr/share/nginx/html and you get exactly
   the ConfigMap's keys there and nothing else — everything the image shipped
   in that directory is hidden.

   Usually that is fine. When you want to drop ONE file into an existing
   directory, it is not.

2. subPath is the answer. Mount at the FILE path, and name the key:

     volumeMounts:
       - name: cfg
         mountPath: /usr/share/nginx/html/index.html
         subPath: index.html

   mountPath is where it lands; subPath is which piece of the volume to take.

3. The equivalent for picking keys without subPath is 'items', which is the
   better choice when you want several files in their own directory:

     volumes:
       - name: cfg
         configMap:
           name: site-config
           items:
             - key: index.html
               path: index.html

4. Verify that the rest of the directory survived — that is the actual
   requirement:

     kubectl -n ${NS} exec onefile -- ls /usr/share/nginx/html
     # index.html  50x.html      <- 50x.html is from the image
     kubectl -n ${NS} exec onefile -- cat /usr/share/nginx/html/index.html

   Without subPath you would see only the two ConfigMap keys and no 50x.html.

5. The one real drawback, worth knowing: a subPath mount does NOT receive
   updates when the ConfigMap changes. A normal ConfigMap mount is refreshed
   by the kubelet within a minute or so; a subPath mount is frozen at
   creation and needs the pod restarted.

The same subPath works for Secrets, PVCs and emptyDir — it is a property of
the mount, not of the volume type."

Q[11]="Write into ${ANS}/q11.txt the name of the PersistentVolume that the claim
'logs' in '${NS}' is bound to.
Just the volume name."
PTS[11]=7
SOL[11]="kubectl -n ${NS} get pvc logs -o jsonpath='{.spec.volumeName}' > ${ANS}/q11.txt"
WALK[11]="1. Binding is recorded on BOTH objects, and knowing both directions is the
   point of this task:

     from the claim:  .spec.volumeName    -> which PV
     from the volume: .spec.claimRef      -> which PVC

     kubectl -n ${NS} get pvc logs -o jsonpath='{.spec.volumeName}{\"\\n\"}'
     kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name} {.spec.claimRef.name}{\"\\n\"}{end}'

2. The listing shows it too, in the VOLUME column:

     kubectl -n ${NS} get pvc logs
     # NAME  STATUS  VOLUME    CAPACITY  ACCESS MODES  STORAGECLASS

3. Write it:

     kubectl -n ${NS} get pvc logs -o jsonpath='{.spec.volumeName}' > ${ANS}/q11.txt

4. Why the reverse lookup matters in practice: when a PV is misbehaving you
   have a volume name and need to know which workload is affected. claimRef
   gives you the namespace and claim; from there:

     kubectl -n <ns> get pods \\
       -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.spec.volumes[*].persistentVolumeClaim.claimName}{\"\\n\"}{end}'

   finds the pods mounting it.

Common traps: reporting the CLAIM name rather than the volume name. Read
which way round the question is asked."

Q[12]="The PersistentVolumeClaim 'inuse' in '${NS}' was deleted, but it is still
there in Terminating.
Make it go away, without force-deleting it and without editing any finalizer."
PTS[12]=7
SOL[12]="kubectl -n ${NS} get pvc inuse -o jsonpath='{.metadata.finalizers}'
#   [\"kubernetes.io/pvc-protection\"]
kubectl -n ${NS} get pods -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.spec.volumes[*].persistentVolumeClaim.claimName}{\"\\n\"}{end}'
#   holder inuse
kubectl -n ${NS} delete pod holder
# the PVC disappears on its own once nothing mounts it"
WALK[12]="1. Look at why it is stuck. The finalizer names the mechanism:

     kubectl -n ${NS} get pvc inuse -o jsonpath='{.metadata.finalizers}'
     # [\"kubernetes.io/pvc-protection\"]

   Storage object in use protection: while any POD still references a PVC,
   the PVC will not be deleted. It is marked Terminating and waits. The same
   applies to PVs, with kubernetes.io/pv-protection.

   This exists to stop somebody deleting the claim out from under a running
   workload and destroying its storage.

2. So the fix is not to fight the finalizer — it is to remove the reason for
   it. Find the pod:

     kubectl -n ${NS} get pods \\
       -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.spec.volumes[*].persistentVolumeClaim.claimName}{\"\\n\"}{end}'
     # holder inuse

   Or from the claim's own events:

     kubectl -n ${NS} describe pvc inuse | tail -5

3. Delete the pod. The PVC then finalises by itself, within seconds:

     kubectl -n ${NS} delete pod holder
     kubectl -n ${NS} get pvc inuse      # NotFound

4. Contrast this with exam 6's finalizer task, which is the OPPOSITE case:

     a finalizer whose controller is GONE     -> clear it by hand; nothing
                                                 else will ever do it
     a finalizer doing its job, as here       -> resolve the condition; the
                                                 controller clears it for you

   Patching pvc-protection away while a pod still mounts the volume is the
   wrong move: you get a pod holding a volume that Kubernetes believes is
   deleted, which is exactly the state the protection exists to prevent.

Common traps: 'kubectl delete pvc --force --grace-period=0'. Force affects
graceful shutdown, not finalizers, so it does not help — and if it appears
to, you have hidden a problem rather than fixed it."

Q[13]="Write into ${ANS}/q13.txt the ACCESS MODE that the PersistentVolume
'pv-recycled' offers, using the short form kubectl prints in its listing.
For example:   RWX"
PTS[13]=5
SOL[13]="kubectl get pv pv-recycled
# ACCESS MODES column shows RWO
echo RWO > ${ANS}/q13.txt"
WALK[13]="1. kubectl abbreviates access modes in the listing, and the exam uses those
   abbreviations in questions, so both forms need to be familiar:

     ReadWriteOnce      RWO
     ReadOnlyMany       ROX
     ReadWriteMany      RWX
     ReadWriteOncePod   RWOP

     kubectl get pv pv-recycled
     # ACCESS MODES: RWO

   The long form is what you write in YAML; the short form is what you read.

2. From the object, if you would rather not read a column:

     kubectl get pv pv-recycled -o jsonpath='{.spec.accessModes[*]}{\"\\n\"}'
     # ReadWriteOnce

3. What they actually mean is about NODES, not pods, and this is the part
   that is usually misremembered:

     RWO    one NODE may mount it read-write. Several pods on that same node
            can use it simultaneously.
     ROX    many nodes, read-only
     RWX    many nodes, read-write — needs a shared filesystem such as NFS or
            CephFS. Most cloud block storage cannot do it.
     RWOP   exactly one POD. The strict version of RWO.

   'My second replica will not start and the volume is RWO' is a very common
   real-world symptom: the second pod landed on a different node.

4. A claim may request fewer modes than the PV offers, but never more."

# ─────────────── grading helpers ───────────────
jp(){ kubectl "$@" 2>/dev/null; }
pvfield(){ jp get pv "$1" -o jsonpath="{$2}"; }
pvcfield(){ jp -n "$NS" get pvc "$1" -o jsonpath="{$2}"; }
filetrim(){ [ -f "$1" ] && tr -d '[:space:]' < "$1"; }
nsok(){ kubectl get ns "$NS" >/dev/null 2>&1; }
podready(){ # name -> Running and all containers ready
  jp -n "$NS" get pod "$1" -o json | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
st=d.get("status") or {}
if st.get("phase")!="Running": sys.exit(1)
cs=st.get("containerStatuses") or []
sys.exit(0 if cs and all(c.get("ready") for c in cs) else 1)
'
}

check(){
  case "$1" in
    1) [ "$(pvfield pv-logs .spec.capacity.storage)" = "3Gi" ] \
       && [ "$(pvfield pv-logs .spec.storageClassName)" = "manual" ] \
       && [ "$(pvfield pv-logs .spec.persistentVolumeReclaimPolicy)" = "Retain" ] \
       && [ "$(pvfield pv-logs '.spec.accessModes[0]')" = "ReadWriteOnce" ] \
       && [ "$(pvfield pv-logs .spec.hostPath.path)" = "/mnt/pv-logs" ] ;;
    2) nsok && [ "$(pvcfield too-big .status.phase)" = "Bound" ] \
       && [ "$(pvcfield too-big .spec.volumeName)" = "pv-small" ] ;;
    # Available AND no stale claimRef — either alone can mislead.
    3) [ "$(pvfield pv-recycled .status.phase)" = "Available" ] \
       && [ -z "$(pvfield pv-recycled '.spec.claimRef.name')" ] ;;
    4) [ "$(jp get sc fast-local -o jsonpath='{.provisioner}')" = "kubernetes.io/no-provisioner" ] \
       && [ "$(jp get sc fast-local -o jsonpath='{.volumeBindingMode}')" = "WaitForFirstConsumer" ] \
       && [ "$(jp get sc fast-local -o jsonpath='{.reclaimPolicy}')" = "Delete" ] \
       && [ "$(jp get sc fast-local -o jsonpath='{.allowVolumeExpansion}')" = "true" ] ;;
    5) [ "$(jp get sc fast-local -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ] ;;
    6) nsok && [ "$(pvcfield logs .status.phase)" = "Bound" ] \
       && [ "$(pvcfield logs .spec.volumeName)" = "pv-logs" ] \
       && podready writer \
       && jp -n "$NS" get pod writer -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
c=d["spec"]["containers"][0]
sys.exit(0 if any(m.get("mountPath")=="/var/log/app" for m in c.get("volumeMounts") or []) else 1)
' ;;
    7) [ -f "$ANS/q7.txt" ] && python3 -c '
import subprocess,sys
want=set(subprocess.run(["kubectl","get","pv","-o",
  "jsonpath={range .items[?(@.spec.persistentVolumeReclaimPolicy==\"Retain\")]}{.metadata.name}{\"\\n\"}{end}"],
  capture_output=True,text=True).stdout.split())
got={l.strip() for l in open(sys.argv[1]) if l.strip()}
sys.exit(0 if want and got==want else 1)
' "$ANS/q7.txt" ;;
    8) nsok && podready sidecar-pair \
       && jp -n "$NS" get pod sidecar-pair -o json | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
sp=d["spec"]
names={c["name"] for c in sp.get("containers") or []}
if not {"writer","reader"} <= names: sys.exit(1)
ed=[v for v in sp.get("volumes") or [] if v.get("emptyDir") is not None]
if not ed: sys.exit(1)
vn={v["name"] for v in ed}
for c in sp["containers"]:
    if c["name"] in ("writer","reader"):
        if not any(m.get("name") in vn and m.get("mountPath")=="/shared"
                   for m in c.get("volumeMounts") or []): sys.exit(1)
sys.exit(0)
' ;;
    9) nsok \
       && [ "$(jp -n "$NS" get sts web -o jsonpath='{.status.readyReplicas}')" = "2" ] \
       && [ "$(jp -n "$NS" get svc web -o jsonpath='{.spec.clusterIP}')" = "None" ] \
       && [ "$(pvcfield data-web-0 .status.phase)" = "Bound" ] \
       && [ "$(pvcfield data-web-1 .status.phase)" = "Bound" ] ;;
    10) nsok && podready onefile \
        && jp -n "$NS" get pod onefile -o json | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
c=d["spec"]["containers"][0]
sys.exit(0 if any(m.get("subPath")=="index.html"
   and m.get("mountPath")=="/usr/share/nginx/html/index.html"
   for m in c.get("volumeMounts") or []) else 1)
' ;;
    11) nsok && [ -n "$(filetrim "$ANS/q11.txt")" ] \
        && [ "$(filetrim "$ANS/q11.txt")" = "$(pvcfield logs .spec.volumeName)" ] ;;
    12) nsok && ! jp -n "$NS" get pvc inuse -o name >/dev/null 2>&1 ;;
    13) [ "$(filetrim "$ANS/q13.txt")" = "RWO" ] ;;
    *) return 2 ;;
  esac
}

storeinfo(){
  printf "\n%s  Storage at a glance%s\n\n" "$BO" "$N"
  printf "  %spersistent volumes%s\n" "$D" "$N"
  kubectl get pv -o custom-columns=\
NAME:.metadata.name,CAP:.spec.capacity.storage,MODES:.spec.accessModes,\
POLICY:.spec.persistentVolumeReclaimPolicy,SC:.spec.storageClassName,\
STATUS:.status.phase,CLAIM:.spec.claimRef.name 2>/dev/null | sed 's/^/    /' \
    || printf "    (none)\n"
  printf "\n  %sclaims in %s%s\n" "$D" "$NS" "$N"
  kubectl -n "$NS" get pvc 2>/dev/null | sed 's/^/    /' || printf "    (namespace missing)\n"
  printf "\n  %sstorage classes%s\n" "$D" "$N"
  kubectl get sc 2>/dev/null | sed 's/^/    /' || printf "    (none)\n"
  printf "\n  %spending claims — why%s\n" "$D" "$N"
  for p in $(kubectl -n "$NS" get pvc -o jsonpath='{range .items[?(@.status.phase=="Pending")]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    printf "    %s: %s\n" "$p" "$(kubectl -n "$NS" describe pvc "$p" 2>/dev/null | grep -A1 Events | tail -1 | cut -c1-90)"
  done
  printf "\n"
}

valid_n(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]; }
need_n(){ if ! valid_n "${1:-}"; then printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2; exit 1; fi; }
show(){
  printf "\n%s┌─ Exam 7 · Task %s/%s ─ %s points%s\n%s└%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N" "$B" "$N"
  echo "${Q[$1]}"
  printf "\n%s  when you are done:  %s %s      stuck?  %s %s%s\n\n" "$D" "$CG" "$1" "$CE" "$1" "$N"
}
grade_one(){
  if check "$1"; then printf "  %s✔%s  %2s  %-3s pts   correct\n" "$G" "$N" "$1" "${PTS[$1]}"; return 0
  else printf "  %s✘%s  %2s  %-3s pts   unsolved or incomplete\n" "$R" "$N" "$1" "0"; return 1; fi
}
grade_all(){
  local got=0 max=0 i
  printf "\n%s  Results%s\n\n" "$BO" "$N"
  for i in $(seq 1 $TOTAL); do max=$(( max + ${PTS[$i]} )); if grade_one "$i"; then got=$(( got + ${PTS[$i]} )); fi; done
  local pct=$(( got * 100 / max ))
  printf "\n  %sSCORE: %s/%s  (%s%%)%s   " "$BO" "$got" "$max" "$pct" "$N"
  if [ "$pct" -ge 66 ]; then printf "%sPASS%s\n\n" "$G$BO" "$N"; else printf "%sFAIL%s %s(the CKA pass mark is 66)%s\n\n" "$R$BO" "$N" "$D" "$N"; fi
}
usage(){
  printf "\n%s  cka-practice · exam 7%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sStorage — 10%% of the CKA.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-18s %s\n" "$CL" "list every task with its points and status"
  printf "    %-18s %s\n" "$CQ N" "show task N"
  printf "    %-18s %s\n" "$CG" "grade everything"
  printf "    %-18s %s\n" "$CE N" "walkthrough"
  printf "    %-18s %s\n" "$CS N" "just the commands"
  printf "    %-18s %s\n" "storeinfo" "every PV, PVC and StorageClass in one screen"
  printf "    %-18s %s\n\n" "$CH" "this text"
  printf "%s  NO DYNAMIC PROVISIONER NEEDED%s\n\n" "$BO" "$N"
  printf "    Every volume here is a static hostPath PV, so the exam works on any\n"
  printf "    cluster. Dynamic provisioning is covered where it matters — the\n"
  printf "    StorageClass fields in tasks 4 and 5 — without needing a CSI driver\n"
  printf "    to actually create anything.\n\n"
  printf "%s  'THERE IS NO STORAGECLASS CALLED manual'%s\n\n" "$BO" "$N"
  printf "    Correct, and there does not need to be. On a PersistentVolume,\n"
  printf "    storageClassName is a matching LABEL, not a reference — nothing looks\n"
  printf "    it up, and 'manual' is the convention for \"administered by hand, do\n"
  printf "    not provision\". Only a PVC that finds no matching PV needs the object\n"
  printf "    to exist, in order to provision from it. %sexplain 1%s has the detail.\n\n" "$BO" "$N"
  printf "%s  THE ONE TO SLOW DOWN ON%s\n\n" "$BO" "$N"
  printf "    Task 3. A Retain PV whose claim was deleted goes to Released and will\n"
  printf "    NEVER rebind, however correct the next claim is — because .spec.claimRef\n"
  printf "    still points at a claim that no longer exists. It looks Available at a\n"
  printf "    glance and behaves as though it is not.\n\n"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    1 → 6      task 6's claim binds to the PV task 1 creates\n"
  printf "    4 → 5      you cannot default a StorageClass that does not exist\n\n"
  printf "    %sFull layout: %s/README.txt%s\n\n" "$D" "$EX7" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 7 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %sstorage · namespace: %s%s\n\n" "$D" "$NS" "$N"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   storeinfo   ·   %s%s\n\n" "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show) need_n "${2:-}" "$CQ"; show "$2" ;;
  grade) if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"; else grade_all; fi ;;
  solve) need_n "${2:-}" "$CS"
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps) need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 7 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  storeinfo|info) storeinfo ;;
  reset) bash "$HERE/setup7.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-practice %s (exam 7)\n" "$VERSION" ;;
  *) printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"; usage; exit 1 ;;
esac
