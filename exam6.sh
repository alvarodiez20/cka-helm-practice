#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam6.sh
#  13 CKA-style general troubleshooting tasks. 100 points.
#  Pass mark: 66.
#
#  Troubleshooting is 30% of the CKA — the highest-weighted
#  domain. Exam 4 covers networking, exam 5 worker nodes; this
#  one covers the control plane, the pod lifecycle, RBAC,
#  storage, quotas and events.
#
#    ./exam6.sh            list the tasks
#    ./exam6.sh q 4        show task 4
#    ./exam6.sh grade      grade everything
#    ./exam6.sh explain 4  walkthrough
#    ./exam6.sh triage     every unhealthy object, one screen
#    ./exam6.sh restore    undo everything setup6.sh broke
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers6"
EX6="$BASE/exam6"
NS="tshoot"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

if [ -n "${EXAM_HOME:-}" ]; then
  CL="exam6"; CQ="q6"; CG="grade6"; CE="explain6"; CS="solve6"; CH="exam6help"
else
  CL="./exam6.sh"; CQ="./exam6.sh q"; CG="./exam6.sh grade"
  CE="./exam6.sh explain"; CS="./exam6.sh solve"; CH="./exam6.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

# ─────────────────────────── 1 ───────────────────────────
Q[1]="No new pod anywhere in this cluster will start. The pod 'sched-canary' in the
default namespace has been Pending since it was created, and 'kubectl describe'
shows it no events at all.
Find out why and fix it, cluster-wide."
PTS[1]=12
SOL[1]="kubectl -n kube-system get pods | grep scheduler     # CrashLoopBackOff
kubectl -n kube-system logs kube-scheduler-\$(hostname) | tail -5
#   stat /etc/kubernetes/scheduler-WRONG.conf: no such file or directory
ls /etc/kubernetes/*.conf                            # scheduler.conf exists
sed -i 's#scheduler-WRONG.conf#scheduler.conf#' \\
  /etc/kubernetes/manifests/kube-scheduler.yaml
# the kubelet notices the file change and recreates the pod, ~30s
kubectl -n kube-system get pods -l component=kube-scheduler -w"
WALK[1]="1. 'Pending with NO events' is a very specific symptom, and it is worth
   recognising instantly. Compare:

     Pending WITH events   the scheduler looked at your pod and refused it —
                           insufficient cpu, untolerated taint, unbound PVC.
     Pending WITHOUT events NOBODY LOOKED. There is no scheduler running to
                           produce an event in the first place.

     kubectl describe pod sched-canary | tail -5
     # Events:  <none>

2. So check the component itself. On a kubeadm cluster the control plane
   runs as static pods in kube-system:

     kubectl -n kube-system get pods
     # kube-scheduler-controlplane   0/1   CrashLoopBackOff

3. Read its logs. The API server is fine, so kubectl still works — that is
   why this is debuggable at all:

     kubectl -n kube-system logs kube-scheduler-\$(hostname) | tail -5
     # stat /etc/kubernetes/scheduler-WRONG.conf: no such file or directory

   If the API server itself were down, kubectl would not answer and you
   would fall back to the node:

     crictl ps -a | grep scheduler
     crictl logs <id>
     ls /var/log/pods/kube-system_kube-scheduler*/

4. Fix the manifest. See what actually exists first:

     ls /etc/kubernetes/*.conf
     # admin.conf  controller-manager.conf  kubelet.conf  scheduler.conf

     sed -i 's#scheduler-WRONG.conf#scheduler.conf#' \\
       /etc/kubernetes/manifests/kube-scheduler.yaml

   You do NOT restart anything. The kubelet watches that directory and
   recreates the pod within about 30 seconds of the file changing. If you
   find yourself running 'kubectl apply' on a static pod manifest, stop —
   the file IS the source of truth.

5. Verify with the canary, not with the pod list:

     kubectl -n kube-system get pods -l component=kube-scheduler
     kubectl get pod sched-canary -o wide     # now has a NODE

Do this task first. Every other fix in this exam creates a new pod, and no
new pod can start while the scheduler is down — you would fix task 2
correctly and still watch it sit Pending.

Common traps: deleting the static pod with kubectl. It comes straight back
from the same broken file, because the kubelet owns it."

# ─────────────────────────── 2 ───────────────────────────
Q[2]="The Deployment 'hungry' in namespace '${NS}' never stays up. Its container is
killed the moment it starts.
Diagnose the cause and fix the Deployment so the pod runs. Give it 64Mi of
memory. Change nothing else."
PTS[2]=8
SOL[2]="kubectl -n ${NS} describe pod -l app=hungry | grep -A3 'Last State'
#   Reason: OOMKilled   Exit Code: 137
kubectl -n ${NS} set resources deploy hungry --limits=memory=64Mi --requests=memory=64Mi"
WALK[2]="1. The status alone does not tell you why. The container's LAST state does:

     kubectl -n ${NS} get pods
     kubectl -n ${NS} describe pod -l app=hungry | grep -A4 'Last State'

     Last State:     Terminated
       Reason:       OOMKilled
       Exit Code:    137

2. Learn the exit codes — they are the fastest diagnosis in the exam:

     0     clean exit; ask why the container did not stay up
     1     application error — read the logs
     2     shell misuse
     126   permission denied
     127   command not found — wrong image or entrypoint
     137   SIGKILL, and with Reason OOMKilled it is the memory limit
     143   SIGTERM, a normal shutdown

   137 is 128+9, and 143 is 128+15. Anything above 128 is 'killed by signal
   N-128', which is why they look arbitrary until you see the pattern.

3. Note that 'kubectl logs' is nearly useless here — the process was killed
   by the kernel, so it never got to complain. This is a case where describe
   beats logs.

     kubectl -n ${NS} get deploy hungry \\
       -o jsonpath='{.spec.template.spec.containers[0].resources}'
     # limits memory 4Mi — nginx cannot even start in that

4. Raise the limit:

     kubectl -n ${NS} set resources deploy hungry \\
       --limits=memory=64Mi --requests=memory=64Mi

5. Verify, and mind the backoff:

     kubectl -n ${NS} get pods -w

   CrashLoopBackOff backs off 10s, 20s, 40s, 80s, 160s, then caps at 5
   minutes. A pod that has been crashing a while can take minutes to come
   back AFTER a correct fix — delete the pod to skip the wait rather than
   concluding your fix did not work.

Common traps: raising requests but not limits. The OOM killer enforces the
LIMIT; requests only affect scheduling."

# ─────────────────────────── 3 ───────────────────────────
Q[3]="The pod 'exiter' in '${NS}' has already died. Its container wrote the reason to
stderr before it went.
Write into ${ANS}/q3.txt two things, on one line separated by a space:
the container's exit code, then the last word of the message it logged.
For example:   7 goodbye"
PTS[3]=6
SOL[3]="kubectl -n ${NS} describe pod exiter | grep -i 'exit code'
#   Exit Code: 3
kubectl -n ${NS} logs exiter --previous
#   FATAL: config missing, giving up
echo '3 up' > ${ANS}/q3.txt"
WALK[3]="1. A container that has restarted has TWO log streams, and the one you want
   is almost never the current one:

     kubectl -n ${NS} logs exiter              # the new attempt, often empty
     kubectl -n ${NS} logs exiter --previous   # the one that crashed

   '--previous' (or '-p') is the single most useful flag in pod debugging,
   and it is the one people forget under time pressure.

2. Get the exit code from describe:

     kubectl -n ${NS} describe pod exiter | grep -A3 'Last State'
     #   Exit Code: 3

   Or straight out of the object, which is easier to script:

     kubectl -n ${NS} get pod exiter \\
       -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'

3. Read what it said before dying:

     kubectl -n ${NS} logs exiter --previous
     # FATAL: config missing, giving up

   Exit code 3 is application-defined — it is not one of the standard ones,
   which is itself the clue that the app chose to exit rather than being
   killed. That means the answer is in the logs, not in describe.

4. Write both:

     echo '3 up' > ${ANS}/q3.txt

Also worth knowing for multi-container pods, where plain 'logs' errors out
and tells you to pick:

     kubectl -n ${NS} logs <pod> -c <container>
     kubectl -n ${NS} logs <pod> --all-containers
     kubectl -n ${NS} logs -l app=exiter --tail=20

Common traps: reading the CURRENT logs, which are empty or from a newer
attempt, and concluding there is nothing to see."

# ─────────────────────────── 4 ───────────────────────────
Q[4]="The Deployment 'badimage' in '${NS}' cannot start its container at all.
Fix it so the pod runs, using the image 'nginx:alpine'."
PTS[4]=8
SOL[4]="kubectl -n ${NS} describe pod -l app=badimage | tail -6
#   Failed to pull image \"nginx:1.99-does-not-exist\" ... not found
kubectl -n ${NS} set image deploy/badimage c=nginx:alpine"
WALK[4]="1. The status names the stage that failed, which narrows it immediately:

     kubectl -n ${NS} get pods
     # badimage-...   0/1   ImagePullBackOff

   ImagePullBackOff means the kubelet never got as far as STARTING a
   container — it could not fetch the image. So there are no application
   logs to read, and there never will be.

2. The events say exactly what it tried:

     kubectl -n ${NS} describe pod -l app=badimage | tail -8
     # Failed to pull image \"nginx:1.99-does-not-exist\":
     #   ... manifest unknown / not found

3. The causes, in the order they actually occur:

     - the tag or repository is misspelled, or the tag never existed
     - the image is private and imagePullSecrets is missing or wrong
     - the registry is unreachable from the node (proxy, DNS, firewall)
     - imagePullPolicy: Always on a node with no egress, for an image that
       is already present locally

4. Fix it. 'set image' takes <container>=<image>, and the container here is
   called 'c':

     kubectl -n ${NS} set image deploy/badimage c=nginx:alpine

   If you cannot remember the container name:

     kubectl -n ${NS} get deploy badimage \\
       -o jsonpath='{.spec.template.spec.containers[*].name}'

5. Verify:

     kubectl -n ${NS} get pods -l app=badimage

Note the difference between the two states you will see: ErrImagePull is the
first failure, ImagePullBackOff is the kubelet backing off after repeated
failures. Same cause; the second just means it has been trying a while.

Common traps: editing the pod instead of the Deployment. The ReplicaSet
recreates it from the template and your change vanishes."

# ─────────────────────────── 5 ───────────────────────────
Q[5]="The Deployment 'needs-config' in '${NS}' is stuck and its container never
starts. It expects configuration that does not exist.
Create what it is missing, in the right namespace, with the key 'GREETING' set
to 'hello'. Do not modify the Deployment."
PTS[5]=8
SOL[5]="kubectl -n ${NS} describe pod -l app=needs-config | tail -5
#   Error: configmap \"app-settings\" not found
kubectl -n ${NS} create configmap app-settings --from-literal=GREETING=hello"
WALK[5]="1. The status is one you should learn to read literally:

     kubectl -n ${NS} get pods
     # needs-config-...   0/1   CreateContainerConfigError

   'CreateContainerConfigError' means the kubelet had the image and was
   assembling the container's configuration — env vars, volumes, secrets —
   and something it needed was not there. Nothing ran, so again there are no
   logs.

2. describe names the missing object:

     kubectl -n ${NS} describe pod -l app=needs-config | tail -6
     # Error: configmap \"app-settings\" not found

3. Find out what shape it has to be, by reading what the pod asks for:

     kubectl -n ${NS} get deploy needs-config \\
       -o jsonpath='{.spec.template.spec.containers[0].envFrom}'
     # [{\"configMapRef\":{\"name\":\"app-settings\"}}]

   envFrom with configMapRef means every key becomes an environment
   variable, so the ConfigMap just needs to exist with the required key.

4. Create it — in the SAME namespace, because ConfigMaps and Secrets are
   namespaced and a pod can only reference its own namespace:

     kubectl -n ${NS} create configmap app-settings --from-literal=GREETING=hello

5. Verify, and note the pod recovers on its own:

     kubectl -n ${NS} get pods -l app=needs-config
     kubectl -n ${NS} exec deploy/needs-config -- env | grep GREETING

The same status covers a family of causes, all found the same way:

     configmap \"x\" not found          create it, or fix the name
     secret \"y\" not found             same
     couldn't find key K in ConfigMap  the object exists, the KEY does not
     Invalid value ... env name        an invalid environment variable name

Common traps: creating it in 'default'. The error looks identical from the
pod's side, because the pod is still looking in its own namespace."

# ─────────────────────────── 6 ───────────────────────────
Q[6]="The Deployment 'probed' in '${NS}' starts, runs for a few seconds, is killed,
and starts again — for ever. The application itself is healthy.
Fix the Deployment so the pod stays up. The container serves HTTP on port 80."
PTS[6]=8
SOL[6]="kubectl -n ${NS} describe pod -l app=probed | grep -i -A2 unhealthy
#   Liveness probe failed: dial tcp ...:8080: connect: connection refused
kubectl -n ${NS} patch deploy probed --type=json \\
  -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/livenessProbe/httpGet/port\",\"value\":80}]'"
WALK[6]="1. The tell is the restart count climbing on a pod that otherwise looks
   fine, and reaches Running each time:

     kubectl -n ${NS} get pods -l app=probed
     # probed-...   1/1   Running   4 (20s ago)   2m

   Restarts with no crash in the logs means something OUTSIDE the container
   is killing it. That is nearly always the liveness probe.

2. describe confirms it, in the events:

     kubectl -n ${NS} describe pod -l app=probed | grep -i -B2 -A2 unhealthy
     # Warning  Unhealthy  Liveness probe failed:
     #   Get \"http://10.244.1.7:8080/\": dial tcp ...: connection refused
     # Normal   Killing    Container c failed liveness probe, will be restarted

3. Compare the probe with reality:

     kubectl -n ${NS} get deploy probed \\
       -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'
     # httpGet path / port 8080

     kubectl -n ${NS} get deploy probed \\
       -o jsonpath='{.spec.template.spec.containers[0].ports}'
     # containerPort 80

   The probe is checking a port nothing listens on. The app is fine; the
   health check is wrong. This is much more common in the real world than a
   genuinely unhealthy app.

4. Point it at 80:

     kubectl -n ${NS} patch deploy probed --type=json \\
       -p='[{\"op\":\"replace\",
             \"path\":\"/spec/template/spec/containers/0/livenessProbe/httpGet/port\",
             \"value\":80}]'

5. Verify the restart count stops moving:

     kubectl -n ${NS} get pods -l app=probed -w

Know the three probes, because using the wrong one causes exactly this:

     liveness    failing RESTARTS the container
     readiness   failing removes the pod from Service endpoints; no restart
     startup     disables the other two until it first succeeds — the right
                 answer for an app that is simply slow to boot

A liveness probe whose initialDelaySeconds is shorter than the app's startup
time produces an infinite restart loop that looks exactly like a crash. If
an app needs 60s to start, that is what startupProbe is for."

# ─────────────────────────── 7 ───────────────────────────
Q[7]="The Deployment 'initstuck' in '${NS}' never reaches Running — it sits in an
Init state. 'kubectl logs' on the pod does not explain why.
Write into ${ANS}/q7.txt the NAME of the container that is holding it up,
then fix the Deployment by removing that container so the pod runs."
PTS[7]=8
SOL[7]="kubectl -n ${NS} get pods -l app=initstuck
#   Init:0/1
kubectl -n ${NS} describe pod -l app=initstuck | grep -A4 'Init Containers'
echo wait-for-it > ${ANS}/q7.txt
kubectl -n ${NS} patch deploy initstuck --type=json \\
  -p='[{\"op\":\"remove\",\"path\":\"/spec/template/spec/initContainers\"}]'"
WALK[7]="1. The status carries the count, and reading it is the whole diagnosis:

     kubectl -n ${NS} get pods -l app=initstuck
     # initstuck-...   0/1   Init:0/1

   'Init:0/1' means zero of one init containers have completed. Init
   containers run in order, to completion, BEFORE any app container starts.
   One that never succeeds blocks the pod for ever.

2. 'kubectl logs' defaults to the app container, which has not started, so
   it tells you nothing. You have to name the init container:

     kubectl -n ${NS} describe pod -l app=initstuck | grep -A6 'Init Containers:'
     # Init Containers:
     #   wait-for-it:
     #     Command: sh -c test -f /shared/ready
     #     State: Waiting  Reason: CrashLoopBackOff

     kubectl -n ${NS} logs <pod> -c wait-for-it

   Getting the name without describe:

     kubectl -n ${NS} get deploy initstuck \\
       -o jsonpath='{.spec.template.spec.initContainers[*].name}'

3. Record it:

     echo wait-for-it > ${ANS}/q7.txt

4. Remove it. A JSON patch 'remove' on the whole array is cleanest:

     kubectl -n ${NS} patch deploy initstuck --type=json \\
       -p='[{\"op\":\"remove\",\"path\":\"/spec/template/spec/initContainers\"}]'

5. Verify:

     kubectl -n ${NS} get pods -l app=initstuck    # 1/1 Running

Init containers are genuinely useful — waiting for a database, running a
migration, fetching a secret — but they fail closed, which is the point.
In the real world you would fix the CONDITION the init container waits for
rather than deleting it; here the task asks you to remove it so the fix is
unambiguous.

Common traps: 'kubectl logs <pod>' returning an error about choosing a
container, and stopping there instead of reading which names it offered."

# ─────────────────────────── 8 ───────────────────────────
Q[8]="The ServiceAccount 'inspector' in '${NS}' must be able to LIST and GET pods in
that namespace, and nothing else anywhere.
Create a Role named 'pod-reader' and a RoleBinding named 'inspector-reads'
that grant exactly that."
PTS[8]=8
SOL[8]="kubectl -n ${NS} create role pod-reader --verb=get,list --resource=pods
kubectl -n ${NS} create rolebinding inspector-reads \\
  --role=pod-reader --serviceaccount=${NS}:inspector
# verify the way the exam expects:
kubectl auth can-i list pods -n ${NS} \\
  --as=system:serviceaccount:${NS}:inspector      # yes"
WALK[8]="1. Confirm the starting point, because 'can-i --as' is the tool this whole
   task is really about:

     kubectl auth can-i list pods -n ${NS} \\
       --as=system:serviceaccount:${NS}:inspector
     # no

   The ServiceAccount username format is worth memorising exactly:

     system:serviceaccount:<namespace>:<name>

2. Create the Role. It is namespaced, and grants verbs on resources:

     kubectl -n ${NS} create role pod-reader --verb=get,list --resource=pods

   Which produces:

     rules:
       - apiGroups: [\"\"]        # core group — pods live here
         resources: [\"pods\"]
         verbs: [\"get\",\"list\"]

3. Bind it. A RoleBinding ties a subject to a Role:

     kubectl -n ${NS} create rolebinding inspector-reads \\
       --role=pod-reader --serviceaccount=${NS}:inspector

   Note --serviceaccount takes <ns>:<name>, not the full system: username.

4. Verify as the subject, not as yourself:

     kubectl auth can-i list pods -n ${NS} \\
       --as=system:serviceaccount:${NS}:inspector      # yes
     kubectl auth can-i delete pods -n ${NS} \\
       --as=system:serviceaccount:${NS}:inspector      # no
     kubectl auth can-i list pods -n default \\
       --as=system:serviceaccount:${NS}:inspector      # no

   The last two matter: the task said 'and nothing else anywhere', so the
   scope has to be wrong in both directions.

The four objects and when each applies:

     Role + RoleBinding                namespaced permissions
     ClusterRole + ClusterRoleBinding  cluster-wide
     ClusterRole + RoleBinding         a reusable ClusterRole applied to ONE
                                       namespace — very common, and the
                                       combination people forget exists
     RoleBinding to a ClusterRole      same thing, seen from the other side

RBAC is purely additive: there are no deny rules, so a permission that
should not exist has to be removed rather than overridden.

Common traps: creating a ClusterRoleBinding, which grants the permission in
every namespace and fails the 'nothing else anywhere' half of the task."

# ─────────────────────────── 9 ───────────────────────────
Q[9]="The PersistentVolumeClaim 'data' in '${NS}' has been Pending since it was
created, and no pod can use it.
Make it bind to the existing PersistentVolume 'tshoot-pv'. You may delete and
recreate the PVC; do not modify or delete the PV."
PTS[9]=8
SOL[9]="kubectl get pv tshoot-pv -o jsonpath='{.spec.storageClassName}'   # slow
kubectl -n ${NS} get pvc data -o jsonpath='{.spec.storageClassName}'  # fast
kubectl -n ${NS} delete pvc data
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data, namespace: ${NS}}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: slow
  resources: {requests: {storage: 1Gi}}
EOF"
WALK[9]="1. Look at both sides. A PVC binds to a PV only when EVERY one of these
   matches, and the failure message rarely says which:

     storageClassName   must be equal
     accessModes        the PV must offer what the claim asks for
     capacity           the PV must be >= the request
     selector           if the claim has one, the PV labels must match
     volumeMode         Filesystem vs Block

     kubectl -n ${NS} get pvc data
     kubectl get pv tshoot-pv

     kubectl get pv tshoot-pv -o jsonpath='{.spec.storageClassName}{\"\\n\"}'
     # slow
     kubectl -n ${NS} get pvc data -o jsonpath='{.spec.storageClassName}{\"\\n\"}'
     # fast

   There is the mismatch. The claim wants 'fast'; the only PV offers 'slow',
   and there is no provisioner for 'fast' to create one dynamically.

2. Check the events too — they distinguish the two very different reasons a
   PVC stays Pending:

     kubectl -n ${NS} describe pvc data | tail -5

     no persistent volumes available for this claim   -> static, no match
     storageclass.storage.k8s.io \"fast\" not found     -> dynamic, no class

3. Most of a PVC's spec is immutable once created — you cannot edit
   storageClassName — so recreate it. The task allows that:

     kubectl -n ${NS} delete pvc data
     # recreate with storageClassName: slow

4. Verify BOTH objects, because binding is two-way:

     kubectl -n ${NS} get pvc data      # STATUS Bound   VOLUME tshoot-pv
     kubectl get pv tshoot-pv           # STATUS Bound   CLAIM ${NS}/data

Two things that catch people out:

   - a PV whose reclaimPolicy is Retain stays 'Released' after its claim is
     deleted, and will NOT rebind to a new claim until you clear
     .spec.claimRef. If this PV shows Released rather than Available, that
     is why.
   - storageClassName: \"\" (empty string) means 'no class', which is
     different from omitting the field, which means 'use the default class'.

Common traps: editing the PV to match the claim. The task forbids it, and in
production the PV is usually the thing you do not control."

# ─────────────────────────── 10 ───────────────────────────
Q[10]="Scaling the Deployment 'needs-config' in '${NS}' to 4 replicas fails: only some
of the pods are ever created, and the ReplicaSet reports an error.
Find the object that is refusing them and write its NAME into
${ANS}/q10.txt. Do not change or delete it."
PTS[10]=7
SOL[10]="kubectl -n ${NS} scale deploy needs-config --replicas=4
kubectl -n ${NS} describe rs -l app=needs-config | tail -5
#   exceeded quota: tight, requested: requests.cpu=..., limited: requests.cpu=500m
kubectl -n ${NS} get resourcequota
echo tight > ${ANS}/q10.txt"
WALK[10]="1. The symptom is specific and often misread: the Deployment says it wants
   4, the ReplicaSet says it created fewer, and the PODS DO NOT EXIST — so
   there is nothing to describe.

     kubectl -n ${NS} scale deploy needs-config --replicas=4
     kubectl -n ${NS} get deploy,rs -l app=needs-config

   When pods are missing rather than Pending, the rejection happened at
   admission — before any pod object was created. So look at the controller
   that tried:

     kubectl -n ${NS} describe rs -l app=needs-config | tail -6
     # Warning FailedCreate ... pods \"needs-config-...\" is forbidden:
     #   exceeded quota: tight, requested: requests.cpu=10m,
     #   used: requests.cpu=500m, limited: requests.cpu=500m

2. That names the object. Confirm it and see how full it is:

     kubectl -n ${NS} get resourcequota
     kubectl -n ${NS} describe resourcequota tight
     # pods           3     8
     # requests.cpu   500m  500m

3. Record the name:

     echo tight > ${ANS}/q10.txt

4. The distinction this task exists to teach:

     Pending pod          the scheduler could not PLACE it. The pod exists.
     No pod at all        admission REFUSED to create it. Look at the
                          ReplicaSet/Job/controller events, not at pods.

   ResourceQuota is admission-time. So are LimitRange, PodSecurity
   admission, and any validating webhook — and all of them produce this same
   'the pod never appeared' shape.

5. A ResourceQuota on requests.cpu or requests.memory has a second effect
   worth knowing: every pod in that namespace must then SPECIFY those
   requests. A pod with no resources block is rejected outright with
   'must specify requests.cpu', which looks baffling until you know a quota
   is in force. LimitRange is what supplies defaults so that does not
   happen.

Common traps: raising the quota. The task says do not change it — and in
practice the quota is usually right and the workload's requests are wrong."

# ─────────────────────────── 11 ───────────────────────────
Q[11]="Write into ${ANS}/q11.txt the name of the pod in namespace '${NS}' that has
the highest restart count.
Just the pod name."
PTS[11]=6
SOL[11]="kubectl -n ${NS} get pods --sort-by='.status.containerStatuses[0].restartCount'
# the last line has the most restarts
kubectl -n ${NS} get pods \\
  --sort-by='.status.containerStatuses[0].restartCount' \\
  -o jsonpath='{.items[-1:].metadata.name}' > ${ANS}/q11.txt"
WALK[11]="1. Restart count is the cheapest health signal in a namespace, and sorting
   by it puts the worst offender at the bottom:

     kubectl -n ${NS} get pods \\
       --sort-by='.status.containerStatuses[0].restartCount'

   --sort-by takes a JSONPath into the object, which means you can sort on
   anything the API exposes, not just the columns shown:

     kubectl -n ${NS} get pods --sort-by=.metadata.creationTimestamp
     kubectl get nodes --sort-by=.status.capacity.memory

2. Take the last entry programmatically rather than reading it off:

     kubectl -n ${NS} get pods \\
       --sort-by='.status.containerStatuses[0].restartCount' \\
       -o jsonpath='{.items[-1:].metadata.name}' > ${ANS}/q11.txt
     cat ${ANS}/q11.txt

   '{.items[-1:]}' is the JSONPath way of saying 'the last one' — worth
   knowing, because kubectl's JSONPath has no 'last()' function.

3. Related things worth having in your fingers:

     kubectl top pods -n ${NS} --sort-by=cpu       needs metrics-server
     kubectl top pods -A --sort-by=memory
     kubectl get pods -A --field-selector status.phase!=Running
     kubectl get pods -A -o wide | grep -v Running

   'kubectl top' is the one that quietly fails on a cluster with no
   metrics-server — 'error: Metrics API not available'. That is not a broken
   cluster, it is a missing add-on, and knowing the difference saves you
   chasing it.

Common traps: pods with several containers. '.status.containerStatuses[0]'
only reads the first one, so a pod whose SECOND container is the one
restarting sorts as if it were healthy."

# ─────────────────────────── 12 ───────────────────────────
Q[12]="Write into ${ANS}/q12.txt every Warning event currently recorded in
namespace '${NS}', oldest first.
The file must contain at least one line and every line must be a Warning."
PTS[12]=6
SOL[12]="kubectl -n ${NS} get events --field-selector type=Warning \\
  --sort-by=.lastTimestamp > ${ANS}/q12.txt"
WALK[12]="1. Events are where a cluster explains itself, and the two flags that make
   them usable are a field selector and a sort:

     kubectl -n ${NS} get events --field-selector type=Warning \\
       --sort-by=.lastTimestamp > ${ANS}/q12.txt
     cat ${ANS}/q12.txt

   Without --sort-by the order is essentially arbitrary, which is why event
   output so often looks like noise.

2. The filters that matter:

     --field-selector type=Warning
     --field-selector type!=Normal
     --field-selector reason=FailedScheduling
     --field-selector reason=BackOff
     --field-selector involvedObject.name=<pod>
     --field-selector involvedObject.kind=Node

   Combine them with commas. There is also a newer dedicated verb, which
   sorts sensibly by default and is worth using when it exists:

     kubectl events -n ${NS} --types=Warning
     kubectl events -n ${NS} --for pod/exiter

3. The single most important limitation: EVENTS EXPIRE. The default TTL is
   one hour. A pod that has been failing since yesterday may have no events
   at all, and 'describe' will show none either — which reads as 'nothing is
   wrong' when the truth is 'nobody has complained recently'.

   When that happens, re-trigger the failure:

     kubectl -n ${NS} delete pod <pod>

   and watch it fail again with fresh events.

4. Across the whole cluster, which is the first command to run on a cluster
   you have never seen:

     kubectl get events -A --sort-by=.lastTimestamp | tail -30

Common traps: the file has to contain Warnings ONLY. Dropping the field
selector gives you Normal events too, which is a different answer."

# ─────────────────────────── 13 ───────────────────────────
Q[13]="The ConfigMap 'stuck-cm' in '${NS}' was deleted, but it is still there and will
not go away.
Get rid of it."
PTS[13]=7
SOL[13]="kubectl -n ${NS} get configmap stuck-cm -o jsonpath='{.metadata.finalizers}'
#   [\"example.com/keep-me\"]
kubectl -n ${NS} patch configmap stuck-cm --type=merge \\
  -p '{\"metadata\":{\"finalizers\":null}}'"
WALK[13]="1. An object that survives 'delete' has a deletionTimestamp set and a
   finalizer that nobody is clearing. Look for both:

     kubectl -n ${NS} get configmap stuck-cm -o yaml | head -12
     # deletionTimestamp: \"2026-07-30T...\"
     # finalizers:
     # - example.com/keep-me

     kubectl -n ${NS} get configmap stuck-cm \\
       -o jsonpath='{.metadata.finalizers}'

2. How deletion actually works, which explains the whole symptom: when
   .metadata.finalizers is non-empty, DELETE does not remove the object. It
   sets deletionTimestamp and waits. Each controller that owns a finalizer
   does its cleanup and removes its own entry. When the list is empty, the
   API server deletes the object for real.

   So an object stuck Terminating means: a finalizer is listed, and whatever
   was supposed to remove it is gone, broken, or never existed.

3. Clear it by hand:

     kubectl -n ${NS} patch configmap stuck-cm --type=merge \\
       -p '{\"metadata\":{\"finalizers\":null}}'

   The object disappears the moment the patch lands, because the
   deletionTimestamp was already set.

4. Verify:

     kubectl -n ${NS} get configmap stuck-cm     # NotFound

Where this really bites is namespaces. A namespace stuck Terminating for
ever is nearly always either a finalizer on the namespace itself, or an
APIService whose backing pod is gone so the namespace controller cannot
enumerate its contents:

     kubectl get ns <ns> -o jsonpath='{.spec.finalizers}'
     kubectl get apiservice | grep -v True     # a False one blocks cleanup

Understand what you are doing when you clear a finalizer: you are skipping
someone's cleanup. For a real controller that may leak an external resource
— a cloud load balancer, a volume. It is the right move when the controller
is genuinely gone, and a bad habit otherwise.

Common traps: 'kubectl delete --force --grace-period=0' does NOT bypass
finalizers. It skips the graceful shutdown of a POD; it has no effect on a
finalizer, and people burn a lot of time on it."

# ─────────────── grading helpers ───────────────
kok(){ kubectl get --raw /healthz >/dev/null 2>&1 || kubectl get ns >/dev/null 2>&1; }
nsok(){ kubectl get ns "$NS" >/dev/null 2>&1; }
jp(){ kubectl "$@" 2>/dev/null; }
filetrim(){ [ -f "$1" ] && tr -d '[:space:]' < "$1"; }
running(){ # selector -> 0 if a Running+Ready pod matches
  kubectl -n "$NS" get pods -l "$1" -o json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
for p in d.get("items") or []:
    st=p.get("status") or {}
    if st.get("phase")!="Running": continue
    cs=st.get("containerStatuses") or []
    if cs and all(c.get("ready") for c in cs): sys.exit(0)
sys.exit(1)
'
}

check(){
  case "$1" in
    # Behavioural: the canary can only get a node if a scheduler is running.
    1) [ -n "$(jp get pod sched-canary -o jsonpath='{.spec.nodeName}')" ] ;;
    2) nsok \
       && [ "$(jp -n "$NS" get deploy hungry -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')" = "64Mi" ] \
       && running app=hungry ;;
    3) [ -f "$ANS/q3.txt" ] \
       && grep -Eqi '^[[:space:]]*3[[:space:]]+up[[:space:]]*$' "$ANS/q3.txt" ;;
    4) nsok \
       && [ "$(jp -n "$NS" get deploy badimage -o jsonpath='{.spec.template.spec.containers[0].image}')" = "nginx:alpine" ] \
       && running app=badimage ;;
    5) nsok \
       && [ "$(jp -n "$NS" get configmap app-settings -o jsonpath='{.data.GREETING}')" = "hello" ] \
       && running app=needs-config ;;
    6) nsok \
       && [ "$(jp -n "$NS" get deploy probed -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}')" = "80" ] \
       && running app=probed ;;
    7) [ "$(filetrim "$ANS/q7.txt")" = "wait-for-it" ] \
       && nsok \
       && [ -z "$(jp -n "$NS" get deploy initstuck -o jsonpath='{.spec.template.spec.initContainers[*].name}')" ] \
       && running app=initstuck ;;
    # Ask the API server itself, rather than re-deriving RBAC from objects.
    8) nsok \
       && kubectl auth can-i list pods -n "$NS" --as="system:serviceaccount:$NS:inspector" 2>/dev/null | grep -qx yes \
       && kubectl auth can-i get pods -n "$NS" --as="system:serviceaccount:$NS:inspector" 2>/dev/null | grep -qx yes \
       && ! kubectl auth can-i delete pods -n "$NS" --as="system:serviceaccount:$NS:inspector" 2>/dev/null | grep -qx yes \
       && ! kubectl auth can-i list pods -n default --as="system:serviceaccount:$NS:inspector" 2>/dev/null | grep -qx yes \
       && jp -n "$NS" get role pod-reader -o name >/dev/null 2>&1 \
       && jp -n "$NS" get rolebinding inspector-reads -o name >/dev/null 2>&1 ;;
    9) nsok \
       && [ "$(jp -n "$NS" get pvc data -o jsonpath='{.status.phase}')" = "Bound" ] \
       && [ "$(jp -n "$NS" get pvc data -o jsonpath='{.spec.volumeName}')" = "tshoot-pv" ] ;;
    10) [ "$(filetrim "$ANS/q10.txt")" = "tight" ] \
        && nsok && jp -n "$NS" get resourcequota tight -o name >/dev/null 2>&1 ;;
    11) nsok && [ -n "$(filetrim "$ANS/q11.txt")" ] \
        && [ "$(filetrim "$ANS/q11.txt")" = "$(kubectl -n "$NS" get pods \
             --sort-by='.status.containerStatuses[0].restartCount' \
             -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null | tr -d '[:space:]')" ] ;;
    12) [ -f "$ANS/q12.txt" ] \
        && [ "$(grep -c . "$ANS/q12.txt")" -ge 1 ] \
        && ! grep -qw Normal "$ANS/q12.txt" \
        && grep -qw Warning "$ANS/q12.txt" ;;
    13) nsok && ! jp -n "$NS" get configmap stuck-cm -o name >/dev/null 2>&1 ;;
    *) return 2 ;;
  esac
}

# ─────────────── triage dashboard ───────────────
triage(){
  printf "\n%s  Triage — everything unhealthy%s\n\n" "$BO" "$N"
  printf "  %scontrol plane%s\n" "$D" "$N"
  kubectl -n kube-system get pods -l tier=control-plane --no-headers 2>/dev/null \
    | awk '{printf "    %-40s %-12s restarts:%s\n",$1,$3,$4}' \
    || printf "    (cannot read kube-system)\n"
  printf "\n  %spods not Running in %s%s\n" "$D" "$NS" "$N"
  kubectl -n "$NS" get pods --no-headers 2>/dev/null \
    | awk '$3!="Running" || $2!~/^([0-9]+)\/\1$/ {printf "    %-34s %-8s %-26s restarts:%s\n",$1,$2,$3,$4}' \
    || printf "    (namespace %s not found)\n" "$NS"
  printf "\n  %spending / unbound%s\n" "$D" "$N"
  printf "    sched-canary node   %s\n" "$(jp get pod sched-canary -o jsonpath='{.spec.nodeName}' || echo '<unscheduled>')"
  printf "    pvc/data            %s -> %s\n" \
    "$(jp -n "$NS" get pvc data -o jsonpath='{.status.phase}' || echo '?')" \
    "$(jp -n "$NS" get pvc data -o jsonpath='{.spec.volumeName}' || echo '<none>')"
  printf "\n  %srecent warnings%s\n" "$D" "$N"
  kubectl -n "$NS" get events --field-selector type=Warning \
    --sort-by=.lastTimestamp --no-headers 2>/dev/null | tail -6 \
    | cut -c1-110 | sed 's/^/    /' || printf "    (none)\n"
  printf "\n"
}

valid_n(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]; }
need_n(){ if ! valid_n "${1:-}"; then
    printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2; exit 1; fi; }
show(){
  printf "\n%s┌─ Exam 6 · Task %s/%s ─ %s points%s\n%s└%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N" "$B" "$N"
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
  for i in $(seq 1 $TOTAL); do
    max=$(( max + ${PTS[$i]} ))
    if grade_one "$i"; then got=$(( got + ${PTS[$i]} )); fi
  done
  local pct=$(( got * 100 / max ))
  printf "\n  %sSCORE: %s/%s  (%s%%)%s   " "$BO" "$got" "$max" "$pct" "$N"
  if [ "$pct" -ge 66 ]; then printf "%sPASS%s\n\n" "$G$BO" "$N"
  else printf "%sFAIL%s %s(the CKA pass mark is 66)%s\n\n" "$R$BO" "$N" "$D" "$N"; fi
}

usage(){
  printf "\n%s  cka-helm-practice · exam 6%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sGeneral cluster troubleshooting — 30%% of the CKA, the biggest domain.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-20s %s\n" "$CL"          "list every task with its points and status"
  printf "    %-20s %s\n" "$CQ N"        "show task N"
  printf "    %-20s %s\n" "$CG"          "grade everything and print the score"
  printf "    %-20s %s\n" "$CE N"        "step-by-step walkthrough, with the reasoning"
  printf "    %-20s %s\n" "$CS N"        "just the commands, no explanation"
  printf "    %-20s %s\n" "triage"       "every unhealthy object in one screen"
  printf "    %-20s %s\n" "exam6restore" "undo everything setup6.sh broke"
  printf "    %-20s %s\n\n" "$CH"        "this text"
  printf "%s  DO TASK 1 FIRST%s\n\n" "$BO" "$N"
  printf "    kube-scheduler is down. Nothing NEW can be placed on a node, so every\n"
  printf "    other fix you make will look like it failed — the corrected Deployment\n"
  printf "    creates a pod and the pod sits Pending for ever.\n\n"
  printf "    'Pending with no events at all' is the signature of a missing\n"
  printf "    scheduler: events mean something LOOKED at your pod and refused it.\n\n"
  printf "%s  WHAT IS DELIBERATELY NOT BROKEN%s\n\n" "$BO" "$N"
  printf "    kube-apiserver and etcd. Breaking either takes kubectl down, and with\n"
  printf "    it the grader — so this exam stops at the scheduler. The walkthrough\n"
  printf "    for task 1 covers what you would do with crictl and /var/log/pods if\n"
  printf "    the API server itself were gone.\n\n"
  printf "%s  THE GROUND IT COVERS%s\n\n" "$BO" "$N"
  printf "    control plane   a static pod manifest with a bad path\n"
  printf "    pod lifecycle   OOMKilled, exit codes, ImagePullBackOff,\n"
  printf "                    CreateContainerConfigError, liveness probes, init containers\n"
  printf "    rbac            Role, RoleBinding, and 'kubectl auth can-i --as'\n"
  printf "    storage         why a PVC will not bind\n"
  printf "    admission       a ResourceQuota refusing pods before they exist\n"
  printf "    observability   --previous, event filtering, sorting by restart count\n"
  printf "    finalizers      an object that will not delete\n\n"
  printf "    %sFull layout, including every planted fault: %s/README.txt%s\n\n" "$D" "$EX6" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 6 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %sgeneral troubleshooting · namespace: %s%s\n\n" "$D" "$NS" "$N"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   triage   ·   %s%s\n\n" "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show) need_n "${2:-}" "$CQ"; show "$2" ;;
  grade)
    if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"; else grade_all; fi ;;
  solve)
    need_n "${2:-}" "$CS"
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps)
    need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 6 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  triage) triage ;;
  restore)
    if [ -x "$EX6/restore.sh" ]; then bash "$EX6/restore.sh"
    else printf "\n  %sno restore script at %s/restore.sh — run setup6.sh first%s\n\n" "$R" "$EX6" "$N"; exit 1; fi ;;
  reset) bash "$HERE/setup6.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s (exam 6)\n" "$VERSION" ;;
  *) printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"; usage; exit 1 ;;
esac
