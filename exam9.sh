#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam9.sh
#  13 CKA-style workloads-and-scheduling tasks. 100 points.
#  Pass mark: 66.
#
#    ./exam9.sh q 4 · grade · explain 4 · workinfo
# ============================================================
set -uo pipefail

BASE="${HOME}"; ANS="$BASE/answers9"; EX9="$BASE/exam9"
NS="work-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

if [ -n "${EXAM_HOME:-}" ]; then
  CL="exam9"; CQ="q9"; CG="grade9"; CE="explain9"; CS="solve9"; CH="exam9help"
else
  CL="./exam9.sh"; CQ="./exam9.sh q"; CG="./exam9.sh grade"
  CE="./exam9.sh explain"; CS="./exam9.sh solve"; CH="./exam9.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

Q[1]="The Deployment 'shop' in namespace '${NS}' was updated to an image that does
not exist and its rollout is stuck.
Return it to the image it was running before that update, using the Deployment's
own history. Do not set the image by hand and do not recreate the Deployment."
PTS[1]=8
SOL[1]="kubectl -n ${NS} rollout history deploy/shop
kubectl -n ${NS} rollout undo deploy/shop
kubectl -n ${NS} rollout status deploy/shop"
WALK[1]="1. See the damage and the history:

     kubectl -n ${NS} get pods            # ImagePullBackOff
     kubectl -n ${NS} rollout status deploy/shop
     # Waiting for deployment ... 1 out of 2 new replicas have been updated

   Note what a stuck rollout looks like: the OLD replicas are still serving.
   A Deployment will not tear down working pods for a new version that never
   becomes Ready — that is RollingUpdate doing its job.

2. Read the history:

     kubectl -n ${NS} rollout history deploy/shop
     # REVISION  CHANGE-CAUSE
     # 1         <none>
     # 2         <none>
     # 3         <none>

     kubectl -n ${NS} rollout history deploy/shop --revision=2

   --revision shows the full pod template for that revision, which is how you
   confirm which image you are going back to before you commit to it.

3. Roll back:

     kubectl -n ${NS} rollout undo deploy/shop                 # previous
     kubectl -n ${NS} rollout undo deploy/shop --to-revision=2 # a specific one

   Like a Helm rollback, this does not erase revision 3 — it creates revision
   4 whose template equals revision 2.

4. Verify:

     kubectl -n ${NS} rollout status deploy/shop     # successfully rolled out
     kubectl -n ${NS} get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'

Where the history actually lives: each revision is a ReplicaSet, kept around
with zero replicas.

     kubectl -n ${NS} get rs

That is also why .spec.revisionHistoryLimit (default 10) matters — set it to 0
and you have no history to roll back to at all.

Common traps: 'kubectl set image' back to the old tag works but is not what
the task asked for, and in real life you may not know what the old tag was.
The history does."

Q[2]="The Deployment 'api' in '${NS}' must update with at most one pod unavailable
and at most one extra pod above the desired count during a rollout.
Set that explicitly on the Deployment."
PTS[2]=7
SOL[2]="kubectl -n ${NS} patch deploy api -p '{\"spec\":{\"strategy\":{\"type\":\"RollingUpdate\",\"rollingUpdate\":{\"maxUnavailable\":1,\"maxSurge\":1}}}}'"
WALK[2]="1. The two knobs, and what they trade off:

     maxUnavailable   how many pods may be DOWN during the rollout. Bounds
                      the capacity you lose.
     maxSurge         how many EXTRA pods may exist above the desired count.
                      Bounds the extra resource you need.

   Both accept a number or a percentage. The default for each is 25%.

2. Set them:

     kubectl -n ${NS} patch deploy api -p '{\"spec\":{\"strategy\":{
       \"type\":\"RollingUpdate\",
       \"rollingUpdate\":{\"maxUnavailable\":1,\"maxSurge\":1}}}}'

3. The combinations worth recognising, because each is a deliberate choice:

     maxUnavailable: 0, maxSurge: 1     never lose capacity. Needs room for
                                        one extra pod. The safe default for
                                        production.
     maxUnavailable: 1, maxSurge: 0     never exceed the replica count. For
                                        a tight quota or a fixed-size pool.
     both 0                             INVALID — the rollout could never
                                        make progress, and the API rejects it.

4. The other strategy type:

     type: Recreate    kill every old pod, then start the new ones. Downtime
                       by design, and the right answer when two versions
                       cannot run at once — a schema migration, or an RWO
                       volume that only one pod can mount.

5. Verify:

     kubectl -n ${NS} get deploy api -o jsonpath='{.spec.strategy}'

Common traps: setting rollingUpdate while type is Recreate. The API rejects
it, because the field only applies to RollingUpdate."

Q[3]="Create a Job named 'batch' in '${NS}' that runs the image busybox:1.36 with
the command 'sh -c \"echo done\"'.
It must run to 6 successful completions, with 2 pods at a time, and give up
after 3 failed attempts."
PTS[3]=8
SOL[3]="kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: batch, namespace: ${NS}}
spec:
  completions: 6
  parallelism: 2
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: c
          image: busybox:1.36
          command: [\"sh\",\"-c\",\"echo done\"]
EOF"
WALK[3]="1. Each phrase in the task is one field:

     'to 6 successful completions'   completions: 6
     '2 pods at a time'              parallelism: 2
     'give up after 3 failed'        backoffLimit: 3

2. The field a Job will not run without: restartPolicy. A pod template's
   default is Always, which is INVALID for a Job — the API rejects it. It has
   to be Never or OnFailure:

     restartPolicy: Never       a failed pod is left; a NEW pod is created
     restartPolicy: OnFailure   the same pod's container is restarted

   'Never' plus a backoffLimit is the combination that leaves you failed pods
   to inspect afterwards, which is usually what you want.

3. Generate the skeleton rather than typing it, then edit — much faster under
   exam conditions:

     kubectl -n ${NS} create job batch --image=busybox:1.36 \\
       --dry-run=client -o yaml -- sh -c 'echo done' > job.yaml
     # add completions, parallelism, backoffLimit

4. Verify:

     kubectl -n ${NS} get job batch
     # COMPLETIONS 6/6   DURATION   AGE
     kubectl -n ${NS} get pods -l job-name=batch

The three shapes of Job, which the exam distinguishes:

     completions unset, parallelism unset   one pod, run once
     completions: N, parallelism: M         a fixed count, M at a time
     completions unset, parallelism: M      a work queue — M workers running
                                            until one succeeds

Also: activeDeadlineSeconds caps the wall-clock time and overrides
backoffLimit, and ttlSecondsAfterFinished cleans the Job up automatically
once it is done."

Q[4]="Create a CronJob named 'nightly' in '${NS}' that runs busybox:1.36 with the
command 'sh -c \"date\"' every day at 03:30.
A run must never overlap a previous one, and the CronJob must be created in a
suspended state."
PTS[4]=8
SOL[4]="kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata: {name: nightly, namespace: ${NS}}
spec:
  schedule: \"30 3 * * *\"
  concurrencyPolicy: Forbid
  suspend: true
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: c
              image: busybox:1.36
              command: [\"sh\",\"-c\",\"date\"]
EOF"
WALK[4]="1. The cron expression, which is the part worth being able to read cold:

     ┌── minute (0-59)
     │ ┌── hour (0-23)
     │ │ ┌── day of month (1-31)
     │ │ │ ┌── month (1-12)
     │ │ │ │ ┌── day of week (0-6, Sunday = 0)
     30 3 * * *      03:30 every day

   Note minute comes FIRST. '3 30 * * *' is 03:00 on the 30th of the month,
   which is a very different answer and an easy mark to lose.

2. concurrencyPolicy, and what each choice means when a run overruns:

     Allow     the default — runs may overlap
     Forbid    skip the new run entirely if the previous one is still going
     Replace   kill the running one and start the new one

3. suspend: true means it is created but never fires. It is how you stage a
   CronJob, and how you stop one during an incident:

     kubectl -n ${NS} patch cronjob nightly -p '{\"spec\":{\"suspend\":true}}'
     kubectl -n ${NS} patch cronjob nightly -p '{\"spec\":{\"suspend\":false}}'

4. Note the nesting, which is where CronJob YAML goes wrong: it is
   spec → jobTemplate → spec → template → spec → containers. Three 'spec's.
   Generating it avoids the whole problem:

     kubectl -n ${NS} create cronjob nightly --image=busybox:1.36 \\
       --schedule='30 3 * * *' --dry-run=client -o yaml -- sh -c date

5. Verify:

     kubectl -n ${NS} get cronjob nightly
     # SCHEDULE     SUSPEND   ACTIVE   LAST SCHEDULE
     # 30 3 * * *   True      0        <none>

   To test one without waiting for the clock:

     kubectl -n ${NS} create job --from=cronjob/nightly manual-run

Also worth knowing: startingDeadlineSeconds, which decides whether a run that
was missed (because the controller was down) still fires when it comes back,
and the history limits successfulJobsHistoryLimit / failedJobsHistoryLimit."

Q[5]="Write into ${ANS}/q5.txt the number of the revision that the Deployment
'shop' in '${NS}' is currently on, according to its rollout history.
Just the number."
PTS[5]=7
SOL[5]="kubectl -n ${NS} rollout history deploy/shop
kubectl -n ${NS} get deploy shop \\
  -o jsonpath='{.metadata.annotations.deployment\\.kubernetes\\.io/revision}' \\
  > ${ANS}/q5.txt"
WALK[5]="1. The current revision is an annotation on the Deployment, which is the
   reliable place to read it:

     kubectl -n ${NS} get deploy shop \\
       -o jsonpath='{.metadata.annotations.deployment\\.kubernetes\\.io/revision}'

   Note the escaped dots — 'deployment.kubernetes.io/revision' contains dots
   that JSONPath would otherwise read as field separators. Escaping them with
   backslashes is a technique worth having, because annotation and label keys
   nearly always contain dots and slashes.

2. The history lists every revision; the highest is the current one:

     kubectl -n ${NS} rollout history deploy/shop

   After task 1's rollback there will be one more revision than you might
   expect — an undo appends a new revision, it does not remove one. If you
   rolled back from 3 to 2, you are now on 4.

3. The same annotation on each ReplicaSet is how you map revisions to
   ReplicaSets:

     kubectl -n ${NS} get rs -o custom-columns=\\
NAME:.metadata.name,REV:.metadata.annotations.deployment\\.kubernetes\\.io/revision,\\
DESIRED:.spec.replicas

4. Write it:

     kubectl -n ${NS} get deploy shop \\
       -o jsonpath='{.metadata.annotations.deployment\\.kubernetes\\.io/revision}' \\
       > ${ANS}/q5.txt

Setting a CHANGE-CAUSE makes history readable, and is worth doing in real
life — the column is otherwise <none> for everything:

     kubectl -n ${NS} annotate deploy shop \\
       kubernetes.io/change-cause='rolled back to 1.27' --overwrite"

Q[6]="Create a HorizontalPodAutoscaler named 'api' in '${NS}' for the Deployment
'api': between 2 and 5 replicas, targeting 70% average CPU utilisation."
PTS[6]=8
SOL[6]="kubectl -n ${NS} autoscale deployment api --min=2 --max=5 --cpu-percent=70"
WALK[6]="1. One command does it:

     kubectl -n ${NS} autoscale deployment api --min=2 --max=5 --cpu-percent=70

   The equivalent object, which is what you would write if the task named
   anything other than CPU:

     apiVersion: autoscaling/v2
     kind: HorizontalPodAutoscaler
     metadata: {name: api, namespace: ${NS}}
     spec:
       scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: api}
       minReplicas: 2
       maxReplicas: 5
       metrics:
         - type: Resource
           resource:
             name: cpu
             target: {type: Utilization, averageUtilization: 70}

2. The prerequisite people forget: an HPA targeting CPU utilisation needs the
   pods to have CPU REQUESTS, because utilisation is a percentage OF THE
   REQUEST. No request, no percentage, and the HPA reports <unknown> for
   ever:

     kubectl -n ${NS} get deploy api \\
       -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'

3. The second prerequisite: metrics-server. Without it the HPA cannot read
   utilisation at all and again shows <unknown>:

     kubectl top pods -n ${NS}
     # error: Metrics API not available   <- no metrics-server

   That is an add-on missing, not a broken HPA, and the object is still
   correct. On a cluster without it this task is graded on the spec.

4. Verify:

     kubectl -n ${NS} get hpa api
     # REFERENCE        TARGETS          MINPODS  MAXPODS  REPLICAS
     # Deployment/api   cpu: <unknown>/70%   2      5        3

5. Note the interaction with a fixed replica count: once an HPA owns a
   Deployment, do not set .spec.replicas by hand — the two fight, and the HPA
   wins on its next cycle.

Common traps: pointing the HPA at a ReplicaSet or a pod. scaleTargetRef must
name something with a scale subresource — Deployment, StatefulSet, ReplicaSet
or a custom resource that implements one."

Q[7]="The Deployment 'api' in '${NS}' must never place two of its own pods on the
same node — the constraint is a hard requirement, not a preference.
Add that rule to the Deployment."
PTS[7]=8
SOL[7]="kubectl -n ${NS} patch deploy api --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/affinity\",\"value\":{
  \"podAntiAffinity\":{\"requiredDuringSchedulingIgnoredDuringExecution\":[{
    \"labelSelector\":{\"matchLabels\":{\"app\":\"api\"}},
    \"topologyKey\":\"kubernetes.io/hostname\"}]}}}]'"
WALK[7]="1. 'Never two on the same node' is pod ANTI-affinity, required, keyed on
   hostname:

     affinity:
       podAntiAffinity:
         requiredDuringSchedulingIgnoredDuringExecution:
           - labelSelector:
               matchLabels:
                 app: api
             topologyKey: kubernetes.io/hostname

2. The three parts, each of which is a decision:

     required...      a hard rule. Unsatisfiable means the pod stays Pending.
     preferred...     a soft rule with a weight (1-100). Best effort.
     topologyKey      the NODE LABEL that defines 'the same place'.
                      kubernetes.io/hostname   -> the same node
                      topology.kubernetes.io/zone -> the same zone

   'IgnoredDuringExecution' on the end of both means the rule is applied when
   scheduling and never re-checked. A pod already running is not evicted if
   the labels later change.

3. The consequence to expect here: 'api' has 3 replicas and a two-node
   cluster has two eligible nodes, so the third pod will sit PENDING with
   'didn't match pod anti-affinity rules'. That is the rule working, not a
   fault — a hard anti-affinity caps your replica count at the number of
   topology domains.

     kubectl -n ${NS} get pods -o wide -l app=api

4. The labelSelector selects the PODS to avoid, not the pods the rule applies
   to. Here they are the same set, which is the usual 'spread my own replicas'
   case, but they need not be — you can also say 'never co-locate with the
   database'.

5. Verify:

     kubectl -n ${NS} get deploy api -o jsonpath='{.spec.template.spec.affinity}'

nodeAffinity is the same shape for choosing NODES by label, and is the modern
replacement for nodeSelector — with the advantage of supporting In, NotIn,
Exists and Gt/Lt operators rather than only equality."

Q[8]="The Deployment 'shop' in '${NS}' must spread its pods evenly across nodes: no
node may run more than one pod more than any other, and a pod that cannot be
placed within that limit must not be scheduled at all.
Use a topology spread constraint on the hostname."
PTS[8]=8
SOL[8]="kubectl -n ${NS} patch deploy shop --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/topologySpreadConstraints\",\"value\":[{
  \"maxSkew\":1,
  \"topologyKey\":\"kubernetes.io/hostname\",
  \"whenUnsatisfiable\":\"DoNotSchedule\",
  \"labelSelector\":{\"matchLabels\":{\"app\":\"shop\"}}}]}]'"
WALK[8]="1. Each phrase maps to one field:

     'no node ... more than one pod more'   maxSkew: 1
     'across nodes'                          topologyKey: kubernetes.io/hostname
     'must not be scheduled at all'          whenUnsatisfiable: DoNotSchedule
     which pods count                        labelSelector

     topologySpreadConstraints:
       - maxSkew: 1
         topologyKey: kubernetes.io/hostname
         whenUnsatisfiable: DoNotSchedule
         labelSelector:
           matchLabels:
             app: shop

2. maxSkew is the maximum permitted DIFFERENCE between the most-loaded and
   least-loaded topology domain — not a per-node cap. With maxSkew 1 and two
   nodes, 3 pods may go 2/1 but never 3/0.

3. whenUnsatisfiable is the hard/soft switch:

     DoNotSchedule    keep the pod Pending rather than break the spread
     ScheduleAnyway   place it anyway; the constraint becomes a preference

4. How this differs from pod anti-affinity, which is the comparison the exam
   is really testing:

     anti-affinity requiredDuring...   a BINARY rule: never together. Three
                                       replicas on two nodes means one is
                                       Pending for ever.
     topology spread maxSkew: 1        a BALANCE rule: as even as possible.
                                       Three replicas on two nodes is 2/1,
                                       which is allowed.

   Spread constraints are almost always the better tool for 'distribute my
   replicas'; anti-affinity is for 'these two things must never share a
   failure domain'.

5. Verify:

     kubectl -n ${NS} get deploy shop \\
       -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'
     kubectl -n ${NS} get pods -o wide -l app=shop

Note nodes missing the topologyKey label are excluded from the calculation
entirely, which is a subtle way for a spread rule to silently do nothing."

Q[9]="Create a PriorityClass named 'high-urgency' with value 100000, which must not
become the cluster default, described as 'for urgent workloads'.
Then make the Deployment 'shop' in '${NS}' use it."
PTS[9]=8
SOL[9]="kubectl apply -f - <<'EOF'
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: {name: high-urgency}
value: 100000
globalDefault: false
description: \"for urgent workloads\"
EOF
kubectl -n ${NS} patch deploy shop -p \\
  '{\"spec\":{\"template\":{\"spec\":{\"priorityClassName\":\"high-urgency\"}}}}'"
WALK[9]="1. A PriorityClass is cluster-scoped, and 'value' is a plain integer at the
   TOP level of the object — not under spec, which catches people out:

     apiVersion: scheduling.k8s.io/v1
     kind: PriorityClass
     metadata: {name: high-urgency}
     value: 100000
     globalDefault: false
     description: \"for urgent workloads\"

2. globalDefault: true would apply this priority to every pod that does not
   name one. Only one PriorityClass in the cluster may set it, and the task
   explicitly rules it out.

3. Attach it by name in the POD TEMPLATE, not on the Deployment itself:

     kubectl -n ${NS} patch deploy shop -p \\
       '{\"spec\":{\"template\":{\"spec\":{\"priorityClassName\":\"high-urgency\"}}}}'

4. What priority actually does, which is two distinct things:

     scheduling order   higher-priority Pending pods are considered first
     PREEMPTION         if a high-priority pod cannot be placed, the scheduler
                        may EVICT lower-priority pods to make room

   Preemption is the part with teeth. It is why a badly chosen priority can
   knock out other people's workloads, and why the two built-in classes sit
   so high:

     kubectl get priorityclass
     # system-cluster-critical   2000000000
     # system-node-critical      2000001000

   You can opt out of the eviction half while keeping the ordering half:

     preemptionPolicy: Never

5. Verify:

     kubectl get priorityclass high-urgency
     kubectl -n ${NS} get deploy shop \\
       -o jsonpath='{.spec.template.spec.priorityClassName}'

Common traps: pods keep the numeric priority they were admitted with. Editing
a PriorityClass's value later does NOT re-prioritise running pods — they have
to be recreated."

Q[10]="Create a PodDisruptionBudget named 'api-pdb' in '${NS}' that keeps at least 2
pods of the Deployment 'api' available during voluntary disruptions."
PTS[10]=8
SOL[10]="kubectl apply -f - <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: api-pdb, namespace: ${NS}}
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: api
EOF"
WALK[10]="1. A PDB selects pods directly — it does not reference the Deployment — so
   the selector must match the pods' labels:

     kubectl -n ${NS} get pods -l app=api --show-labels

     spec:
       minAvailable: 2
       selector:
         matchLabels:
           app: api

2. minAvailable or maxUnavailable, one or the other, never both. Both accept
   a number or a percentage:

     minAvailable: 2       at least 2 must stay up
     minAvailable: 50%     at least half
     maxUnavailable: 1     at most 1 may be taken down at a time

3. The word that matters is VOLUNTARY. A PDB constrains the eviction API and
   nothing else:

     it DOES protect against   kubectl drain, cluster autoscaler scale-down,
                               node upgrades — anything using evictions
     it does NOT protect against   a node crashing, an OOM kill, someone
                                   running 'kubectl delete pod'

   A PDB is a promise about planned work, not a guarantee of availability.

4. This is the object that makes 'kubectl drain' hang, which is the
   connection to exam 8. With 3 replicas and minAvailable 2, draining a node
   holding 2 of them can only evict one — the drain waits, correctly, and
   says so:

     Cannot evict pod as it would violate the pod's disruption budget

   A PDB whose minAvailable equals the replica count blocks drains for ever,
   which is a genuinely common production mistake.

5. Verify:

     kubectl -n ${NS} get pdb api-pdb
     # NAME      MIN AVAILABLE   ALLOWED DISRUPTIONS
     # api-pdb   2               1

   ALLOWED DISRUPTIONS is the number to read: 0 means nothing can be evicted
   right now."

Q[11]="The Deployment 'api' in '${NS}' takes a long time to start, and its container
must not be restarted while it is still booting.
Add a startup probe that checks TCP port 80, allowing up to 60 seconds before
declaring failure, using 12 attempts 5 seconds apart."
PTS[11]=7
SOL[11]="kubectl -n ${NS} patch deploy api --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/startupProbe\",\"value\":{
  \"tcpSocket\":{\"port\":80},
  \"failureThreshold\":12,
  \"periodSeconds\":5}}]'"
WALK[11]="1. The arithmetic the task is describing: failureThreshold × periodSeconds
   is the total grace period.

     12 × 5 = 60 seconds

     startupProbe:
       tcpSocket:
         port: 80
       failureThreshold: 12
       periodSeconds: 5

2. What a startup probe is FOR. While it is running, the liveness and
   readiness probes are disabled entirely. Once it succeeds once, it never
   runs again and the other two take over.

   That solves a specific and very common problem: an app that takes two
   minutes to boot, with a liveness probe that starts checking after ten
   seconds, gets killed and restarted for ever. It looks exactly like a crash
   loop and is not one.

3. Before startupProbe existed the workaround was a large
   initialDelaySeconds on the liveness probe — which is worse, because it
   delays detection of real failures for the whole life of the container.
   A startup probe is generous only during startup and strict afterwards.

4. The three probe types are interchangeable in shape:

     httpGet:    {path: /healthz, port: 8080}
     tcpSocket:  {port: 80}
     exec:       {command: [\"cat\",\"/tmp/ready\"]}

   And the timings:

     initialDelaySeconds   wait before the FIRST check
     periodSeconds         how often
     timeoutSeconds        how long one check may take
     failureThreshold      consecutive failures before acting
     successThreshold      consecutive successes to be considered up

5. Verify:

     kubectl -n ${NS} get deploy api \\
       -o jsonpath='{.spec.template.spec.containers[0].startupProbe}'
     kubectl -n ${NS} rollout status deploy/api

Common traps: adding a startup probe to a container that is already Running
happily changes nothing visible, so verify the FIELD rather than the pod."

Q[12]="Scale the Deployment 'shop' in '${NS}' to exactly 4 replicas, and make sure it
keeps only the 3 most recent revisions in its rollout history."
PTS[12]=7
SOL[12]="kubectl -n ${NS} scale deploy shop --replicas=4
kubectl -n ${NS} patch deploy shop -p '{\"spec\":{\"revisionHistoryLimit\":3}}'"
WALK[12]="1. Two independent changes:

     kubectl -n ${NS} scale deploy shop --replicas=4
     kubectl -n ${NS} patch deploy shop -p '{\"spec\":{\"revisionHistoryLimit\":3}}'

2. 'kubectl scale' has a conditional form worth knowing, which makes a script
   safe to re-run against a Deployment somebody else may have changed:

     kubectl -n ${NS} scale deploy shop --replicas=4 --current-replicas=2

   It only acts if the current count matches, otherwise it errors.

3. revisionHistoryLimit (default 10) is the number of OLD ReplicaSets kept
   with zero replicas so you can roll back to them:

     kubectl -n ${NS} get rs -l app=shop

   Setting it to 0 deletes all history and makes 'rollout undo' impossible —
   occasionally what you want on a cluster with thousands of Deployments,
   usually not.

4. Note that lowering the limit does not immediately delete the extra
   ReplicaSets; the controller prunes them on the next rollout.

5. Verify:

     kubectl -n ${NS} get deploy shop \\
       -o jsonpath='{.spec.replicas} {.spec.revisionHistoryLimit}{\"\\n\"}'

If an HPA owns the Deployment, scaling by hand is pointless — the autoscaler
overrides it within a cycle. That is why task 6's HPA targets 'api' and this
task targets 'shop'."

Q[13]="Write into ${ANS}/q13.txt the name of every pod in '${NS}' that is NOT in
the Running phase — one name per line. If they are all Running, the file must
be empty but must exist."
PTS[13]=8
SOL[13]="kubectl -n ${NS} get pods --field-selector status.phase!=Running \\
  -o jsonpath='{range .items[*]}{.metadata.name}{\"\\n\"}{end}' > ${ANS}/q13.txt"
WALK[13]="1. A field selector does the filtering server-side, which is the right tool
   and much faster than grepping a full listing:

     kubectl -n ${NS} get pods --field-selector status.phase!=Running

2. Emit just the names:

     kubectl -n ${NS} get pods --field-selector status.phase!=Running \\
       -o jsonpath='{range .items[*]}{.metadata.name}{\"\\n\"}{end}' \\
       > ${ANS}/q13.txt

   Note this produces an empty file when everything is healthy, which is the
   correct answer and is why the task says the file must still exist.

3. The pod phases, which is the set this filters on:

     Pending     accepted, but not all containers are running yet
     Running     bound to a node, at least one container running
     Succeeded   all containers exited 0 and will not restart
     Failed      all terminated, at least one non-zero
     Unknown     the node cannot be reached

   Phase is coarse. A pod that is CrashLoopBackOff is still phase Running,
   and a pod that is not Ready is too. So this filter finds Pending and
   Failed pods but NOT a crashlooping one — which is worth knowing before you
   trust it as a health check.

4. For the fuller picture you want readiness, not phase:

     kubectl -n ${NS} get pods -o wide | grep -v ' Running '
     kubectl -n ${NS} get pods \\
       -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.status.containerStatuses[*].ready}{\"\\n\"}{end}'

   And across the cluster, the one-liner worth remembering:

     kubectl get pods -A --field-selector status.phase!=Running

Depending on which tasks you have completed, this file may legitimately list
pods left Pending by task 7's anti-affinity or task 8's spread constraint —
those are the rules working, not failures."

# ─────────────── grading helpers ───────────────
jp(){ kubectl "$@" 2>/dev/null; }
dp(){ jp -n "$NS" get deploy "$1" -o jsonpath="{$2}"; }
filetrim(){ [ -f "$1" ] && tr -d '[:space:]' < "$1"; }
nsok(){ kubectl get ns "$NS" >/dev/null 2>&1; }
pyspec(){ # kind name -- python expr on 'd'
  local kind="$1" name="$2" expr="$3"
  jp -n "$NS" get "$kind" "$name" -o json | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
try: sys.exit(0 if eval("("+sys.argv[1]+")") else 1)
except Exception: sys.exit(1)
' "$expr"
}

check(){
  case "$1" in
    # Rolled back means: not the broken tag any more, AND the rollout has
    # actually completed. Both readings must be non-empty — comparing two
    # empty strings would otherwise pass against no cluster at all.
    1) nsok || return 1
       img="$(dp shop '.spec.template.spec.containers[0].image')"
       [ -n "$img" ] || return 1
       case "$img" in *9.99-broken*) return 1 ;; esac
       rr="$(dp shop .status.readyReplicas)"; want="$(dp shop .spec.replicas)"
       [ -n "$rr" ] && [ -n "$want" ] && [ "$rr" = "$want" ] ;;
    2) nsok && pyspec deploy api '
d["spec"].get("strategy",{}).get("type")=="RollingUpdate"
and str(d["spec"]["strategy"].get("rollingUpdate",{}).get("maxUnavailable"))=="1"
and str(d["spec"]["strategy"].get("rollingUpdate",{}).get("maxSurge"))=="1"' ;;
    3) nsok && pyspec job batch '
d["spec"].get("completions")==6 and d["spec"].get("parallelism")==2
and d["spec"].get("backoffLimit")==3
and (d["spec"]["template"]["spec"].get("containers") or [{}])[0].get("image")=="busybox:1.36"' ;;
    4) nsok && pyspec cronjob nightly '
d["spec"].get("schedule")=="30 3 * * *"
and d["spec"].get("concurrencyPolicy")=="Forbid"
and d["spec"].get("suspend") is True' ;;
    5) nsok && [ -n "$(filetrim "$ANS/q5.txt")" ] \
       && [ "$(filetrim "$ANS/q5.txt")" \
            = "$(dp shop '.metadata.annotations.deployment\.kubernetes\.io/revision')" ] ;;
    6) nsok && pyspec hpa api '
d["spec"].get("minReplicas")==2 and d["spec"].get("maxReplicas")==5
and (d["spec"].get("scaleTargetRef") or {}).get("name")=="api"
and (
  any((m.get("resource") or {}).get("name")=="cpu"
      and ((m.get("resource") or {}).get("target") or {}).get("averageUtilization")==70
      for m in d["spec"].get("metrics") or [])
  or d["spec"].get("targetCPUUtilizationPercentage")==70
)' ;;
    7) nsok && pyspec deploy api '
any(t.get("topologyKey")=="kubernetes.io/hostname"
    and ((t.get("labelSelector") or {}).get("matchLabels") or {}).get("app")=="api"
    for t in ((d["spec"]["template"]["spec"].get("affinity") or {})
              .get("podAntiAffinity") or {})
             .get("requiredDuringSchedulingIgnoredDuringExecution") or [])' ;;
    8) nsok && pyspec deploy shop '
any(c.get("maxSkew")==1 and c.get("topologyKey")=="kubernetes.io/hostname"
    and c.get("whenUnsatisfiable")=="DoNotSchedule"
    for c in d["spec"]["template"]["spec"].get("topologySpreadConstraints") or [])' ;;
    9) [ "$(jp get priorityclass high-urgency -o jsonpath='{.value}')" = "100000" ] \
       && [ "$(jp get priorityclass high-urgency -o jsonpath='{.globalDefault}')" != "true" ] \
       && [ -n "$(jp get priorityclass high-urgency -o jsonpath='{.description}')" ] \
       && nsok && [ "$(dp shop .spec.template.spec.priorityClassName)" = "high-urgency" ] ;;
    10) nsok && pyspec pdb api-pdb '
str(d["spec"].get("minAvailable"))=="2"
and ((d["spec"].get("selector") or {}).get("matchLabels") or {}).get("app")=="api"' ;;
    11) nsok && pyspec deploy api '
(lambda p: p is not None
   and (p.get("tcpSocket") or {}).get("port")==80
   and p.get("failureThreshold")==12
   and p.get("periodSeconds")==5
)(d["spec"]["template"]["spec"]["containers"][0].get("startupProbe"))' ;;
    12) nsok && [ "$(dp shop .spec.replicas)" = "4" ] \
        && [ "$(dp shop .spec.revisionHistoryLimit)" = "3" ] ;;
    # Empty is a legitimate answer, so the file must EXIST and must match.
    13) nsok && [ -f "$ANS/q13.txt" ] && python3 -c '
import subprocess,sys
want=set(subprocess.run(["kubectl","-n",sys.argv[2],"get","pods",
  "--field-selector","status.phase!=Running","-o",
  "jsonpath={range .items[*]}{.metadata.name}{\"\\n\"}{end}"],
  capture_output=True,text=True).stdout.split())
got={l.strip() for l in open(sys.argv[1]) if l.strip()}
sys.exit(0 if got==want else 1)
' "$ANS/q13.txt" "$NS" ;;
    *) return 2 ;;
  esac
}

workinfo(){
  printf "\n%s  Workloads at a glance%s\n\n" "$BO" "$N"
  for k in deploy rs job cronjob hpa pdb; do
    out="$(kubectl -n "$NS" get "$k" --no-headers 2>/dev/null)"
    printf "  %s%s%s\n" "$D" "$k" "$N"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /' || printf "    (none)\n"
  done
  printf "  %spods%s\n" "$D" "$N"
  kubectl -n "$NS" get pods -o wide --no-headers 2>/dev/null \
    | awk '{printf "    %-34s %-8s %-20s %s\n",$1,$2,$3,$7}' || printf "    (none)\n"
  printf "\n  %spriorityclasses%s\n" "$D" "$N"
  kubectl get priorityclass --no-headers 2>/dev/null | awk '{printf "    %-28s %s\n",$1,$2}'
  printf "\n"
}

valid_n(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]; }
need_n(){ if ! valid_n "${1:-}"; then printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2; exit 1; fi; }
show(){
  printf "\n%s┌─ Exam 9 · Task %s/%s ─ %s points%s\n%s└%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N" "$B" "$N"
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
  printf "\n%s  cka-helm-practice · exam 9%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sWorkloads and scheduling — 15%% of the CKA.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-16s %s\n" "$CL" "list every task with its points and status"
  printf "    %-16s %s\n" "$CQ N" "show task N"
  printf "    %-16s %s\n" "$CG" "grade everything"
  printf "    %-16s %s\n" "$CE N" "walkthrough"
  printf "    %-16s %s\n" "$CS N" "just the commands"
  printf "    %-16s %s\n" "workinfo" "deployments, jobs, HPAs, PDBs and pods in one screen"
  printf "    %-16s %s\n\n" "$CH" "this text"
  printf "%s  TWO THINGS THAT LOOK LIKE FAILURES AND ARE NOT%s\n\n" "$BO" "$N"
  printf "    After task 7, one 'api' pod goes Pending. A hard pod anti-affinity on\n"
  printf "    hostname caps replicas at the number of nodes — that is the rule\n"
  printf "    working, and it is exactly why task 8 contrasts it with a topology\n"
  printf "    spread constraint, which balances instead of forbidding.\n\n"
  printf "    Without metrics-server the HPA in task 6 shows <unknown>/70%% and never\n"
  printf "    scales. That is a missing add-on, not a broken object, and the task is\n"
  printf "    graded on the spec.\n\n"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    1 before 5    the revision number you report depends on the rollback\n"
  printf "    13 last       it reports whatever is Pending, which tasks 7 and 8 change\n\n"
  printf "    %sFull layout: %s/README.txt%s\n\n" "$D" "$EX9" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 9 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %sworkloads and scheduling · namespace: %s%s\n\n" "$D" "$NS" "$N"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   workinfo   ·   %s%s\n\n" "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show) need_n "${2:-}" "$CQ"; show "$2" ;;
  grade) if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"; else grade_all; fi ;;
  solve) need_n "${2:-}" "$CS"
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps) need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 9 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  workinfo|info) workinfo ;;
  reset) bash "$HERE/setup9.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s (exam 9)\n" "$VERSION" ;;
  *) printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"; usage; exit 1 ;;
esac
