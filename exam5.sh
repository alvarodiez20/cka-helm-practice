#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam5.sh
#  13 CKA-style worker node failure tasks. 100 points.
#  Pass mark: 66.
#
#    ./exam5.sh            list the tasks
#    ./exam5.sh q 4        show task 4
#    ./exam5.sh grade      grade everything, print the score
#    ./exam5.sh explain 4  step-by-step walkthrough of task 4
#    ./exam5.sh nodeinfo   a quick health dashboard for the node
#    ./exam5.sh restore    undo everything setup5.sh broke
#    ./exam5.sh help       full usage
#    ./exam5.sh reset      re-seed (runs setup5.sh)
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers5"
EX5="$BASE/exam5"
NODE="${CKA_NODE:-node01}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

if [ -n "${EXAM_HOME:-}" ]; then
  CL="exam5"; CQ="q5"; CG="grade5"; CE="explain5"; CS="solve5"; CH="exam5help"
else
  CL="./exam5.sh"; CQ="./exam5.sh q"; CG="./exam5.sh grade"
  CE="./exam5.sh explain"; CS="./exam5.sh solve"; CH="./exam5.sh help"
fi

SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes"
onnode(){ $SSH "$NODE" "$@" 2>/dev/null; }

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

# ─────────────────────────── 1 ───────────────────────────
Q[1]="The node '${NODE}' is NotReady and no workload will run on it.
Investigate and bring it back to Ready.
There is more than one fault, and fixing one reveals the next. Do not delete
the node object and do not rejoin it to the cluster."
PTS[1]=14
SOL[1]="ssh ${NODE}
systemctl status kubelet                  # dead. start it:
systemctl start kubelet
systemctl status kubelet                  # now crashlooping. read the logs:
journalctl -u kubelet -n 30 --no-pager
#   'unable to load client CA file /etc/kubernetes/pki/WRONG-CA-FILE.crt'
sed -i 's#WRONG-CA-FILE.crt#ca.crt#' /var/lib/kubelet/config.yaml
systemctl restart kubelet                 # running now, but still NotReady:
journalctl -u kubelet -n 30 --no-pager
#   'Unable to register node ... dial tcp ...:6553: connect: connection refused'
sed -i 's#:6553#:6443#' /etc/kubernetes/kubelet.conf
systemctl restart kubelet
exit
kubectl get nodes                         # Ready"
WALK[1]="1. NotReady means the API server has stopped hearing from the node's
   kubelet. The kubelet is always the first suspect, because it is what
   reports node status. Confirm what the control plane thinks:

     kubectl get nodes
     kubectl describe node ${NODE} | grep -A6 Conditions

   'Kubelet stopped posting node status' is the phrase to look for.

2. The answer is never on the control plane for this class of problem. Get
   onto the node:

     ssh ${NODE}
     systemctl status kubelet

   FAULT 1: the unit is 'inactive (dead)'. Start it:

     systemctl start kubelet

3. Check again rather than assuming:

     systemctl status kubelet

   FAULT 2: now it is 'activating (auto-restart)' — a crashloop. A service
   that will not stay up is a configuration problem, and the logs say which:

     journalctl -u kubelet -n 30 --no-pager

     failed to construct kubelet dependencies: unable to load client CA file
     /etc/kubernetes/pki/WRONG-CA-FILE.crt: no such file or directory

   The kubelet cannot authenticate to the API server without its CA, so it
   exits. Find where that setting lives — the unit file tells you which
   config the kubelet reads:

     systemctl cat kubelet
     # Environment=\"KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml\"

     ls /etc/kubernetes/pki/          # ca.crt is right there
     sed -i 's#WRONG-CA-FILE.crt#ca.crt#' /var/lib/kubelet/config.yaml
     systemctl restart kubelet

   sed is faster and safer than vi here — no chance of breaking the YAML.

4. Check a third time. This is the step people skip.

     systemctl status kubelet     # active (running)
     kubectl get nodes            # STILL NotReady

   FAULT 3: the process is healthy but the node is not registering. Back to
   the logs:

     journalctl -u kubelet -n 30 --no-pager

     \"Unable to register node with API server\" err=\"Post
     https://controlplane:6553/api/v1/nodes: dial tcp ...:6553:
     connect: connection refused\"

   6553 is not the API server port. 6443 is. The kubelet reaches the API
   server through a kubeconfig, exactly like kubectl does, and
   'systemctl cat kubelet' names two of them:

     --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf
     --kubeconfig=/etc/kubernetes/kubelet.conf

   The bootstrap one is only used while joining. The live one is the second:

     sed -i 's#:6553#:6443#' /etc/kubernetes/kubelet.conf
     systemctl restart kubelet

5. Verify from the control plane, and give it a few seconds:

     exit
     kubectl get nodes            # Ready

The loop worth internalising, because it is the whole task:

     systemctl status kubelet     is it running?
       dead        -> start it
       auto-restart-> config is bad, read journalctl
       running     -> it is running and still wrong, read journalctl anyway
     systemctl cat kubelet        which files does it read?
     journalctl -u kubelet        what is it actually complaining about?

Common traps: restarting the kubelet and declaring victory without
re-checking 'kubectl get nodes'. Two of the three faults here leave the
service looking fine from one angle or another."

# ─────────────────────────── 2 ───────────────────────────
Q[2]="The kubelet on '${NODE}' must also start automatically the next time the node
boots. Right now it would not."
PTS[2]=6
SOL[2]="ssh ${NODE} systemctl enable kubelet
# or, combining with a start:  systemctl enable --now kubelet"
WALK[2]="1. 'active' and 'enabled' are different questions, and mixing them up is
   how a cluster comes back from a reboot with a missing node:

     active   is it running right now       systemctl is-active kubelet
     enabled  will it start at boot         systemctl is-enabled kubelet

     ssh ${NODE} systemctl is-enabled kubelet
     # disabled

2. Enable it:

     ssh ${NODE} systemctl enable kubelet

   'systemctl enable --now kubelet' does both in one go, which is the habit
   worth having — it is the standard closing move on any kubeadm node.

3. Verify both:

     ssh ${NODE} systemctl is-enabled kubelet    # enabled
     ssh ${NODE} systemctl is-active kubelet     # active

Note what 'enable' actually does: it creates a symlink in
/etc/systemd/system/multi-user.target.wants/. On a kubeadm node the kubelet
also has a drop-in at /etc/systemd/system/kubelet.service.d/10-kubeadm.conf,
which is where kubeadm puts its flags — worth knowing because that is the
file 'systemctl cat kubelet' shows you appended to the main unit."

# ─────────────────────────── 3 ───────────────────────────
Q[3]="'${NODE}' is Ready, but the scheduler still refuses to place any new pod on it
because it has been marked unschedulable.
Return it to normal service. Do not remove any taint in this task."
PTS[3]=7
SOL[3]="kubectl uncordon ${NODE}"
WALK[3]="1. Spot it in the STATUS column — this is the giveaway:

     kubectl get nodes
     # ${NODE}   Ready,SchedulingDisabled   <none>   9d   v1.35.1

   'Ready' and 'SchedulingDisabled' together mean the kubelet is perfectly
   healthy and somebody cordoned the node.

2. The flag behind it is a field on the node object:

     kubectl get node ${NODE} -o jsonpath='{.spec.unschedulable}'
     # true

3. Undo it:

     kubectl uncordon ${NODE}
     kubectl get nodes            # Ready, no SchedulingDisabled

Know the three verbs and what each actually does, because the exam picks
between them deliberately:

     kubectl cordon <n>     sets .spec.unschedulable=true. Existing pods stay
                            put; no NEW pods are scheduled.
     kubectl drain <n>      cordons AND evicts. Needs --ignore-daemonsets
                            (DaemonSet pods are not evictable) and usually
                            --delete-emptydir-data. This is the real
                            pre-maintenance command.
     kubectl uncordon <n>   sets it back to schedulable.

A drain that hangs is nearly always a PodDisruptionBudget refusing the
eviction, or a bare pod with no controller — 'drain' will not delete those
without --force.

Common traps: cordon is not a taint. Uncordoning does not clear taints, and
removing taints does not uncordon. This node has both problems; this task is
only the cordon."

# ─────────────────────────── 4 ───────────────────────────
Q[4]="A NoSchedule taint on '${NODE}' is left over from maintenance and is keeping
workloads off the node.
Remove that taint, and only that one."
PTS[4]=8
SOL[4]="kubectl taint node ${NODE} maintenance-"
WALK[4]="1. List what is on the node. Two ways, and the jsonpath one is worth
   knowing because describe output is long:

     kubectl describe node ${NODE} | grep -i taint
     kubectl get node ${NODE} -o jsonpath='{.spec.taints}'
     # [{\"effect\":\"NoSchedule\",\"key\":\"maintenance\",\"value\":\"true\"}]

2. Remove it by KEY followed by a minus. The value is not needed:

     kubectl taint node ${NODE} maintenance-

   The trailing '-' is the whole syntax for removal. To be explicit about
   which effect you are removing when a key has several:

     kubectl taint node ${NODE} maintenance=true:NoSchedule-

3. Verify it is gone and nothing else went with it:

     kubectl get node ${NODE} -o jsonpath='{.spec.taints}'

Taints and tolerations, briefly, since the next task is the other side of
this coin:

     NoSchedule         do not place new pods here
     PreferNoSchedule   try not to, but it is allowed
     NoExecute          do not place, AND evict what is already running

Control-plane nodes carry node-role.kubernetes.io/control-plane:NoSchedule
by default, which is why ordinary workloads avoid them.

Common traps: 'kubectl taint node ${NODE} maintenance=true:NoSchedule'
without the minus ADDS the taint again. And removing a taint the cluster
relies on — the control-plane one, or a disk-pressure taint the kubelet set
itself — causes different problems. The kubelet re-applies its own condition
taints anyway, so fighting those means fixing the underlying condition."

# ─────────────────────────── 5 ───────────────────────────
Q[5]="The Deployment 'ssd-only' in namespace 'node-lab' has one replica stuck
Pending. It requires a node advertising fast storage.
Make it run on '${NODE}' by changing the NODE, not the Deployment."
PTS[5]=8
SOL[5]="kubectl label node ${NODE} disktype=ssd"
WALK[5]="1. Find out why the scheduler will not place it. The events at the bottom
   of describe are the answer, always:

     kubectl -n node-lab get pods
     kubectl -n node-lab describe pod -l app=ssd-only | tail -15

     0/2 nodes are available: 1 node(s) didn't match Pod's node
     affinity/selector, 1 node(s) had untolerated taint {...}

2. Read what the pod is asking for:

     kubectl -n node-lab get deploy ssd-only \\
       -o jsonpath='{.spec.template.spec.nodeSelector}'
     # {\"disktype\":\"ssd\"}

   Then check what the node advertises:

     kubectl get node ${NODE} --show-labels

   No disktype label. A nodeSelector is a hard requirement: no matching
   label, no scheduling, forever.

3. The task says fix the node, so add the label:

     kubectl label node ${NODE} disktype=ssd

   The scheduler retries continuously, so the pod moves within seconds.

4. Verify:

     kubectl get node ${NODE} --show-labels | tr ',' '\\n' | grep disktype
     kubectl -n node-lab get pods -o wide      # Running, on ${NODE}

Note this task depends on tasks 3 and 4. A label fixes the selector, but a
cordon or a NoSchedule taint will still keep the pod off the node — three
independent gates, all of which must be open.

Removing a label uses the same minus as taints:

     kubectl label node ${NODE} disktype-

Common traps: labelling the wrong object. 'kubectl label deploy' or
'kubectl label pod' both succeed and change nothing relevant — the label has
to be on the NODE for a nodeSelector to match."

# ─────────────────────────── 6 ───────────────────────────
Q[6]="A static pod must run on '${NODE}', managed directly by its kubelet rather
than by the API server.
Its manifest is to live in /etc/kubernetes/manifests-exam5, and the pod must
be named 'agent' and run the image nginx:alpine.
The kubelet is not currently configured to read that directory."
PTS[6]=10
SOL[6]="ssh ${NODE}
# 1. tell the kubelet where to look (the setting was removed):
echo 'staticPodPath: /etc/kubernetes/manifests-exam5' >> /var/lib/kubelet/config.yaml
# 2. drop the manifest in
mkdir -p /etc/kubernetes/manifests-exam5
cat > /etc/kubernetes/manifests-exam5/agent.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: agent
spec:
  containers:
    - name: agent
      image: nginx:alpine
EOF
systemctl restart kubelet
exit
kubectl get pods -A | grep agent      # agent-${NODE}"
WALK[6]="1. A static pod is created by the kubelet from a file on disk. The API
   server never schedules it — it only learns about it afterwards, as a
   mirror pod. That is why static pods survive an unreachable control plane,
   and why the control plane hosts its own components this way.

   The kubelet only watches ONE directory, named by staticPodPath in its
   config. Check whether it is set:

     ssh ${NODE}
     grep staticPodPath /var/lib/kubelet/config.yaml
     # (nothing)

   That is the first half of the task. A manifest in a directory nobody
   watches does nothing at all.

2. Set it, then create the manifest:

     echo 'staticPodPath: /etc/kubernetes/manifests-exam5' >> /var/lib/kubelet/config.yaml
     mkdir -p /etc/kubernetes/manifests-exam5
     cat > /etc/kubernetes/manifests-exam5/agent.yaml <<'EOF'
     apiVersion: v1
     kind: Pod
     metadata:
       name: agent
     spec:
       containers:
         - name: agent
           image: nginx:alpine
     EOF

   Note there is no 'namespace' in the manifest and no nodeName. Static pods
   land in 'default' unless the manifest says otherwise, and they always run
   on the node whose kubelet read the file.

3. The kubelet re-reads its config only on restart:

     systemctl restart kubelet

   New FILES in the directory are picked up automatically after that, but
   the staticPodPath setting itself needs the restart.

4. Verify from the control plane. The mirror pod's name has the node name
   appended, which is how you recognise a static pod at a glance:

     kubectl get pods -A | grep agent
     # default   agent-${NODE}   1/1   Running

5. The thing to remember about static pods: you cannot delete them with
   kubectl. 'kubectl delete pod agent-${NODE}' removes the mirror, the
   kubelet notices the file is still there, and it comes straight back. To
   remove one you delete the FILE:

     rm /etc/kubernetes/manifests-exam5/agent.yaml

   On a real kubeadm control plane that directory is
   /etc/kubernetes/manifests, holding kube-apiserver, etcd,
   kube-controller-manager and kube-scheduler. Moving a file out of there is
   the standard way to take the API server down deliberately — and
   accidentally, which is worth knowing.

Common traps: forgetting the restart, so the config change never takes
effect; and expecting a static pod to obey taints or nodeSelectors. It does
not — the scheduler is not involved."

# ─────────────────────────── 7 ───────────────────────────
Q[7]="The DaemonSet 'node-agent' in 'node-lab' is supposed to run on EVERY node in
the cluster, including the control plane. It currently skips it.
Fix the DaemonSet so it runs everywhere. Do not remove any taint from any node."
PTS[7]=8
SOL[7]="kubectl -n node-lab patch ds node-agent --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\",\"value\":[{\"key\":\"node-role.kubernetes.io/control-plane\",\"operator\":\"Exists\",\"effect\":\"NoSchedule\"}]}]'"
WALK[7]="1. Compare what the DaemonSet wants with what it got:

     kubectl -n node-lab get ds node-agent
     # DESIRED CURRENT READY  ...
     # 1       1       1

   One, on a two-node cluster. A DaemonSet targets every node that it is
   ALLOWED to run on, so 'desired 1' means the controller already decided
   one node is off limits.

2. Which node, and why:

     kubectl -n node-lab get pods -o wide     # only on ${NODE}
     kubectl describe node controlplane | grep -i taint
     # node-role.kubernetes.io/control-plane:NoSchedule

   The control plane is tainted by default. The DaemonSet has no matching
   toleration, so the controller excludes that node entirely.

3. The task forbids removing the taint — correctly, since that taint is
   what keeps ordinary workloads off your control plane. The right fix is a
   toleration on the workload:

     kubectl -n node-lab patch ds node-agent --type=json \\
       -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\",\"value\":
            [{\"key\":\"node-role.kubernetes.io/control-plane\",
              \"operator\":\"Exists\",\"effect\":\"NoSchedule\"}]}]'

   'operator: Exists' with no value tolerates the taint whatever its value —
   the right choice here, because that taint's value is empty.

   The blunt instrument, which tolerates everything, is what system
   DaemonSets like kube-proxy and the CNI actually use:

     tolerations:
       - operator: Exists

4. Verify DESIRED goes to 2 and both become ready:

     kubectl -n node-lab get ds node-agent
     kubectl -n node-lab get pods -o wide

Worth knowing: DaemonSet pods are scheduled by the normal scheduler these
days, using nodeAffinity the controller writes for you — but they are still
exempt from eviction by 'kubectl drain' unless you pass --ignore-daemonsets.

Common traps: adding the toleration to the wrong key. It is
'node-role.kubernetes.io/control-plane'; older clusters used
'node-role.kubernetes.io/master', and some still carry both."

# ─────────────────────────── 8 ───────────────────────────
Q[8]="The Deployment 'greedy' in 'node-lab' will never schedule: it asks for more
CPU than any node in this cluster has.
Change its CPU request to 100m so that it runs. Change nothing else."
PTS[8]=8
SOL[8]="kubectl -n node-lab set resources deploy greedy --requests=cpu=100m"
WALK[8]="1. Read the events, not the pod status. 'Pending' tells you nothing on its
   own; the scheduler explains itself:

     kubectl -n node-lab describe pod -l app=greedy | tail -12
     # 0/2 nodes are available: 2 Insufficient cpu.

   'Insufficient cpu' is unambiguous — this is a resource fit problem, not a
   taint, selector or affinity problem.

2. See what it is asking for, and what exists:

     kubectl -n node-lab get deploy greedy \\
       -o jsonpath='{.spec.template.spec.containers[0].resources}'
     # {\"requests\":{\"cpu\":\"64\",\"memory\":\"16Mi\"}}

     kubectl describe node ${NODE} | grep -A5 Allocatable
     kubectl describe node ${NODE} | grep -A8 'Allocated resources'

   Scheduling is decided on REQUESTS against ALLOCATABLE, never on actual
   usage. A node that is 5% busy will still refuse a pod requesting more
   CPU than it has left unrequested.

3. Right-size it:

     kubectl -n node-lab set resources deploy greedy --requests=cpu=100m

   '100m' is 0.1 of a core. Note '64' means 64 whole cores — a missing 'm'
   is a factor of a thousand, and is the actual bug here in miniature.

4. Verify:

     kubectl -n node-lab get pods -o wide
     kubectl -n node-lab get deploy greedy \\
       -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'

Allocatable is not capacity: it is capacity minus what the kubelet reserves
for the system and for itself (--system-reserved, --kube-reserved) minus the
eviction threshold. That is why a 2-core node never lets you request 2 CPUs.

Common traps: raising limits instead of requests. Limits do not affect
scheduling at all — only requests do."

# ─────────────────────────── 9 ───────────────────────────
Q[9]="Write into ${ANS}/q9.txt the single line from the scheduler's own
event for the Pending 'greedy' pod that states why it could not be placed —
before you fix it. If you have already fixed it, the phrase to record is the
reason it gave.
The file must contain the words 'Insufficient cpu'."
PTS[9]=6
SOL[9]="kubectl -n node-lab describe pod -l app=greedy | grep -i insufficient \\
  > ${ANS}/q9.txt
# or from the event stream:
kubectl -n node-lab get events --field-selector reason=FailedScheduling \\
  -o custom-columns=MSG:.message --no-headers | head -1 > ${ANS}/q9.txt"
WALK[9]="1. Two places carry scheduling failures, and knowing both is the point:

     kubectl -n node-lab describe pod -l app=greedy | tail -12
     kubectl -n node-lab get events --field-selector reason=FailedScheduling

   describe is quicker to read; the events API is what you filter and script
   against. Note events expire — one hour by default — so a pod that has
   been Pending since yesterday may have no event left, and describe will
   show none either. In that case you re-trigger it by deleting the pod.

2. Capture the line:

     kubectl -n node-lab describe pod -l app=greedy \\
       | grep -i insufficient > ${ANS}/q9.txt
     cat ${ANS}/q9.txt
     # 0/2 nodes are available: 2 Insufficient cpu. preemption: ...

3. Learn to read the grammar of that message, because it names the exact
   predicate that failed and each one points somewhere different:

     Insufficient cpu / memory            requests exceed allocatable
     had untolerated taint {...}          taint vs toleration
     didn't match Pod's node affinity     nodeSelector / nodeAffinity
     node(s) were unschedulable           the node is cordoned
     didn't match pod anti-affinity       spread rules
     had volume node affinity conflict    the PV is pinned to another zone

   'preemption: 0/2 nodes are available' on the end means the scheduler also
   considered evicting lower-priority pods to make room, and that would not
   have helped either.

Common traps: writing the whole describe output to the file. The task asks
for the line that states the reason."

# ─────────────────────────── 10 ───────────────────────────
Q[10]="Write into ${ANS}/q10.txt the container runtime and the kubelet
version that '${NODE}' reports, in exactly this format and nothing else:

  <containerRuntimeVersion> <kubeletVersion>

for example:   containerd://2.1.4 v1.35.1"
PTS[10]=7
SOL[10]="kubectl get node ${NODE} \\
  -o jsonpath='{.status.nodeInfo.containerRuntimeVersion} {.status.nodeInfo.kubeletVersion}' \\
  > ${ANS}/q10.txt"
WALK[10]="1. Everything the kubelet reports about its host lives under
   .status.nodeInfo. Look at all of it once — it answers a lot of
   troubleshooting questions without an ssh:

     kubectl get node ${NODE} -o jsonpath='{.status.nodeInfo}' | tr ',' '\\n'

     architecture, bootID, containerRuntimeVersion, kernelVersion,
     kubeProxyVersion, kubeletVersion, machineID, operatingSystem,
     osImage, systemUUID

2. Pull the two fields. A jsonpath template can hold literal text, including
   the space between them:

     kubectl get node ${NODE} \\
       -o jsonpath='{.status.nodeInfo.containerRuntimeVersion} {.status.nodeInfo.kubeletVersion}' \\
       > ${ANS}/q10.txt
     cat ${ANS}/q10.txt

   The same thing is in the wide listing, if you would rather read a table:

     kubectl get nodes -o wide

3. Why this matters in practice: containerRuntimeVersion tells you which CRI
   the node runs and therefore which tool to debug it with. 'containerd://'
   means crictl on the node:

     ssh ${NODE} crictl ps
     ssh ${NODE} crictl -r unix:///run/containerd/containerd.sock ps

   Note docker is not a CRI any more — dockershim was removed in 1.24 — so
   a modern node reports containerd or cri-o.

   kubeletVersion matters for skew: a kubelet may run up to three minor
   versions behind the API server, never ahead. A node whose kubelet is too
   old is a genuine and easily-missed cause of odd behaviour.

Common traps: adding a trailing newline is fine, but adding labels like
'runtime: ' is not — the task asked for the two values and nothing else."

# ─────────────────────────── 11 ───────────────────────────
Q[11]="Write into ${ANS}/q11.txt the value of 'clusterDNS' that the kubelet on
'${NODE}' is configured with — read from the kubelet's own configuration file
on the node, not from any Service.
One IP address, nothing else."
PTS[11]=6
SOL[11]="ssh ${NODE} grep -A1 '^clusterDNS' /var/lib/kubelet/config.yaml
ssh ${NODE} \"awk '/^clusterDNS:/{getline; gsub(/[ -]/,\\\"\\\"); print; exit}' \\
  /var/lib/kubelet/config.yaml\" > ${ANS}/q11.txt"
WALK[11]="1. The kubelet decides what goes into every pod's /etc/resolv.conf, and it
   takes that from its own config file — not from the kube-dns Service
   object. Find the config the way you always do:

     ssh ${NODE}
     systemctl cat kubelet | grep -- --config
     # --config=/var/lib/kubelet/config.yaml

2. Read the setting. It is a LIST, so the value is on the next line:

     grep -A2 '^clusterDNS' /var/lib/kubelet/config.yaml
     # clusterDNS:
     # - 10.96.0.10
     # clusterDomain: cluster.local

3. Get just the address into the file:

     ssh ${NODE} \"awk '/^clusterDNS:/{getline; gsub(/[ -]/,\\\"\\\"); print; exit}' \\
       /var/lib/kubelet/config.yaml\" > ${ANS}/q11.txt
     cat ${ANS}/q11.txt

4. Why read it here rather than from the Service: these are two independent
   pieces of configuration that are supposed to agree, and cluster-wide DNS
   failure is what happens when they do not.

     kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}'
     ssh ${NODE} grep -A1 clusterDNS /var/lib/kubelet/config.yaml

   If the kubelet points at an address the DNS Service no longer has, every
   pod on that node gets a resolv.conf aimed at nothing, while CoreDNS looks
   perfectly healthy from the control plane. Comparing the two is the check.

   The matching pod-side view:

     kubectl -n node-lab exec <pod> -- cat /etc/resolv.conf

Common traps: reporting the clusterDomain, or reporting the Service IP from
kubectl when the task said to read the node's file. They are usually the same
value, which is exactly why the distinction is worth practising."

# ─────────────────────────── 12 ───────────────────────────
Q[12]="Write into ${ANS}/q12.txt the number of pods — across all namespaces —
that are currently assigned to '${NODE}'.
Just the number."
PTS[12]=6
SOL[12]="kubectl get pods -A --field-selector spec.nodeName=${NODE} \\
  --no-headers | wc -l > ${ANS}/q12.txt"
WALK[12]="1. 'Which pods are on this node' is the question you ask before draining
   one, and after a node misbehaves. The wrong way is to list everything and
   read the NODE column by eye. The right way is a field selector, evaluated
   server-side:

     kubectl get pods -A --field-selector spec.nodeName=${NODE}

2. Count them:

     kubectl get pods -A --field-selector spec.nodeName=${NODE} \\
       --no-headers | wc -l > ${ANS}/q12.txt
     cat ${ANS}/q12.txt

3. Field selectors are not label selectors, and the difference catches
   people out: they filter on object FIELDS, and only on the handful of
   fields the API server indexes. For pods the useful ones are:

     --field-selector spec.nodeName=${NODE}
     --field-selector status.phase=Running
     --field-selector status.phase!=Running          # what is not healthy
     --field-selector spec.nodeName=${NODE},status.phase=Failed

   Combine with a label selector when you need both:

     kubectl get pods -A --field-selector spec.nodeName=${NODE} -l app=node-agent

4. 'kubectl describe node' also summarises this, with the resource totals
   that matter for scheduling:

     kubectl describe node ${NODE} | grep -A12 'Non-terminated Pods'

Note the count changes as you solve other tasks — the static pod from task 6
and the DaemonSet pod from task 7 both live here. Answer this one last, and
if the grader disagrees with you, re-run the command: something you did
since has moved a pod."

# ─────────────────────────── 13 ───────────────────────────
Q[13]="Write into ${ANS}/q13.txt the name of the systemd unit file setting that
tells the kubelet on '${NODE}' which configuration file to read, exactly as it
appears on the command line — the flag and its value, nothing else.
For example:   --config=/some/path.yaml"
PTS[13]=6
SOL[13]="ssh ${NODE} systemctl cat kubelet | grep -o '\\-\\-config=[^\\\" ]*' \\
  | head -1 > ${ANS}/q13.txt"
WALK[13]="1. This is the command that unlocks every kubelet problem, so it is worth a
   task of its own. The kubelet's behaviour is spread across a unit file, a
   kubeadm drop-in, and a YAML config — and one command shows you all of it:

     ssh ${NODE} systemctl cat kubelet

   You get the main unit, then:

     # /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
     Environment=\"KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=... --kubeconfig=/etc/kubernetes/kubelet.conf\"
     Environment=\"KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml\"
     ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS ...

   Every file you might need to fix is named there. That is why tasks 1, 6
   and 11 all start with this command.

2. Extract the flag:

     ssh ${NODE} systemctl cat kubelet | grep -o '\\-\\-config=[^\\\" ]*' | head -1 \\
       > ${ANS}/q13.txt
     cat ${ANS}/q13.txt
     # --config=/var/lib/kubelet/config.yaml

3. The three-way split, and which one to reach for:

     kubelet.service + 10-kubeadm.conf   FLAGS. Change these and you must
                                         'systemctl daemon-reload' before
                                         restarting.
     /var/lib/kubelet/config.yaml        the KubeletConfiguration object:
                                         clientCAFile, staticPodPath,
                                         clusterDNS, cgroupDriver, evictionHard.
                                         A restart is enough.
     /etc/kubernetes/kubelet.conf        the kubeconfig it uses to talk to the
                                         API server.

   Most settings moved out of flags into config.yaml years ago, and most
   flags are deprecated — so when a task says 'configure the kubelet', the
   YAML is usually where it belongs.

4. If a change appears to do nothing, it is nearly always one of two things:

     systemctl daemon-reload      you edited a unit file and skipped this
     systemctl restart kubelet    you edited config.yaml and skipped this

Common traps: reporting the path without the flag, or reporting the
kubeconfig flag instead. The task asked for the one that points at the
configuration FILE."

# ─────────────── grading helpers ───────────────
# Several checks here are negations — "the taint is gone", "the node is not
# cordoned". Those pass trivially when kubectl cannot reach the cluster at
# all, which would award points for an absent cluster. Every such check is
# gated on the node object actually being readable first.
nodeexists(){ kubectl get node "$NODE" >/dev/null 2>&1; }
nodefield(){ kubectl get node "$NODE" -o jsonpath="{$1}" 2>/dev/null; }
noderready(){ # Ready condition == True
  kubectl get node "$NODE" -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
for c in (d.get("status") or {}).get("conditions") or []:
    if c.get("type")=="Ready":
        sys.exit(0 if c.get("status")=="True" else 1)
sys.exit(1)
'
}
hastaint(){ # key -> 0 if present
  kubectl get node "$NODE" -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
k=sys.argv[1]
sys.exit(0 if any(t.get("key")==k for t in (d.get("spec") or {}).get("taints") or []) else 1)
' "$1"
}
filetrim(){ [ -f "$1" ] && tr -d '[:space:]' < "$1"; }
podrunning(){ # ns selector -> 0 if at least one Running pod matches
  kubectl -n "$1" get pods -l "$2" -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if any((p.get("status") or {}).get("phase")=="Running"
                  for p in d.get("items") or []) else 1)
'
}
dsready(){ # ns name -> prints "<desired> <ready>"
  kubectl -n "$1" get ds "$2" -o jsonpath='{.status.desiredNumberScheduled} {.status.numberReady}' 2>/dev/null
}
nodecount(){ kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' '; }
podsonnode(){ kubectl get pods -A --field-selector "spec.nodeName=$NODE" --no-headers 2>/dev/null | wc -l | tr -d ' '; }

check(){
  case "$1" in
    1) noderready ;;
    2) [ "$(onnode systemctl is-enabled kubelet)" = "enabled" ] ;;
    3) nodeexists \
       && case "$(nodefield .spec.unschedulable)" in ""|false) return 0 ;; *) return 1 ;; esac ;;
    4) nodeexists && ! hastaint maintenance ;;
    5) [ "$(nodefield '.metadata.labels.disktype')" = "ssd" ] \
       && podrunning node-lab app=ssd-only ;;
    # The mirror pod of a static pod is named <pod>-<node>, which is the
    # cheapest proof that the kubelet (not the scheduler) created it.
    6) kubectl get pod "agent-${NODE}" -o json >/dev/null 2>&1 \
       && [ "$(kubectl get pod "agent-${NODE}" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] \
       && [ "$(kubectl get pod "agent-${NODE}" -o jsonpath='{.spec.nodeName}' 2>/dev/null)" = "$NODE" ] ;;
    # 'desired' and 'ready' must both reach the node count, and the node
    # count must be real — with no cluster everything is 0 and 0>=0 would
    # otherwise pass.
    7) nc="$(nodecount)"; [ "${nc:-0}" -ge 2 ] || return 1
       set -- $(dsready node-lab node-agent)
       [ "${1:-0}" -ge "$nc" ] && [ "${2:-0}" -ge "$nc" ] ;;
    8) [ "$(kubectl -n node-lab get deploy greedy -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)" = "100m" ] \
       && podrunning node-lab app=greedy ;;
    9) [ -f "$ANS/q9.txt" ] && grep -qi 'insufficient cpu' "$ANS/q9.txt" ;;
    10) [ -f "$ANS/q10.txt" ] \
        && [ "$(filetrim "$ANS/q10.txt")" \
             = "$(nodefield .status.nodeInfo.containerRuntimeVersion)$(nodefield .status.nodeInfo.kubeletVersion)" ] ;;
    11) [ -f "$ANS/q11.txt" ] \
        && [ -n "$(filetrim "$ANS/q11.txt")" ] \
        && [ "$(filetrim "$ANS/q11.txt")" \
             = "$(onnode "awk '/^clusterDNS:/{getline; gsub(/[ -]/,\"\"); print; exit}' /var/lib/kubelet/config.yaml" | tr -d '[:space:]')" ] ;;
    12) nodeexists && [ -f "$ANS/q12.txt" ] \
        && [ "$(filetrim "$ANS/q12.txt")" = "$(podsonnode)" ] ;;
    # Compare the trimmed contents directly; no need for grep or a process
    # substitution, which is not portable to sh anyway.
    13) [ "$(filetrim "$ANS/q13.txt")" = "--config=/var/lib/kubelet/config.yaml" ] ;;
    *) return 2 ;;
  esac
}

# ─────────────── node dashboard ───────────────
nodeinfo(){
  printf "\n%s  %s at a glance%s\n\n" "$BO" "$NODE" "$N"
  printf "  %sfrom the control plane%s\n" "$D" "$N"
  kubectl get node "$NODE" -o wide 2>/dev/null | sed 's/^/    /'
  printf "\n  %sconditions%s\n" "$D" "$N"
  kubectl get node "$NODE" -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit()
for c in (d.get("status") or {}).get("conditions") or []:
    print("    %-18s %-6s %s" % (c.get("type"), c.get("status"), (c.get("reason") or "")))
'
  printf "\n  %sscheduling gates%s\n" "$D" "$N"
  printf "    unschedulable   %s\n" "$(nodefield .spec.unschedulable || echo '<none>')"
  printf "    taints          %s\n" "$(nodefield '.spec.taints[*].key' || echo '<none>')"
  printf "    disktype label  %s\n" "$(nodefield '.metadata.labels.disktype' || echo '<none>')"
  printf "    pods assigned   %s\n" "$(podsonnode)"

  printf "\n  %sfrom the node itself (over ssh)%s\n" "$D" "$N"
  if onnode true; then
    printf "    kubelet active   %s\n" "$(onnode systemctl is-active kubelet || echo unknown)"
    printf "    kubelet enabled  %s\n" "$(onnode systemctl is-enabled kubelet || echo unknown)"
    printf "    staticPodPath    %s\n" "$(onnode "grep '^staticPodPath:' /var/lib/kubelet/config.yaml | cut -d' ' -f2" || echo '<unset>')"
    printf "    clientCAFile     %s\n" "$(onnode "grep -o 'clientCAFile: .*' /var/lib/kubelet/config.yaml | cut -d' ' -f2" || echo '?')"
    printf "    apiserver in kubeconfig  %s\n" "$(onnode "grep -o 'server: .*' /etc/kubernetes/kubelet.conf | head -1 | cut -d' ' -f2" || echo '?')"
    printf "\n  %slast kubelet errors%s\n" "$D" "$N"
    onnode "journalctl -u kubelet -p err -n 5 --no-pager -o cat" 2>/dev/null | sed 's/^/    /' \
      || printf "    (none, or journal unreadable)\n"
  else
    printf "    %scannot ssh to %s%s\n" "$R" "$NODE" "$N"
  fi
  printf "\n"
}

valid_n(){
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]
}
need_n(){
  if ! valid_n "${1:-}"; then
    printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" \
      "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2
    exit 1
  fi
}
show(){
  printf "\n%s┌─ Exam 5 · Task %s/%s ─ %s points%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N"
  printf "%s└%s\n" "$B" "$N"
  echo "${Q[$1]}"
  printf "\n%s  when you are done:  %s %s      stuck?  %s %s%s\n\n" \
    "$D" "$CG" "$1" "$CE" "$1" "$N"
}
grade_one(){
  local n="$1"
  if check "$n"; then
    printf "  %s✔%s  %2s  %-3s pts   %s\n" "$G" "$N" "$n" "${PTS[$n]}" "correct"
    return 0
  else
    printf "  %s✘%s  %2s  %-3s pts   %s\n" "$R" "$N" "$n" "0" "unsolved or incomplete"
    return 1
  fi
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
  printf "\n%s  cka-helm-practice · exam 5%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sWorker node failure troubleshooting. Target node: %s%s\n\n" "$D" "$NODE" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-20s %s\n" "$CL"           "list every task with its points and status"
  printf "    %-20s %s\n" "$CQ N"         "show task N"
  printf "    %-20s %s\n" "$CG"           "grade everything and print the score"
  printf "    %-20s %s\n" "$CG N"         "grade task N only"
  printf "    %-20s %s\n" "$CE N"         "step-by-step walkthrough, with the reasoning"
  printf "    %-20s %s\n" "$CS N"         "just the commands, no explanation"
  printf "    %-20s %s\n" "nodeinfo"      "health dashboard for the node, both sides"
  printf "    %-20s %s\n" "exam5restore"  "undo every break and put the node back"
  printf "    %-20s %s\n" "$CH"           "this text"
  printf "    %-20s %s\n\n" "$CL reset"   "re-seed exam 5 from scratch"
  printf "%s  THIS EXAM BREAKS A REAL NODE%s\n\n" "$BO" "$N"
  printf "    setup5.sh stops the kubelet on %s, points its clientCAFile at a\n" "$NODE"
  printf "    file that does not exist, changes the API server port in its\n"
  printf "    kubeconfig, deletes staticPodPath, then cordons and taints the node.\n\n"
  printf "    Both files are backed up on the node first, and %sexam5restore%s puts\n" "$BO" "$N"
  printf "    everything back and waits for Ready. Use it if you get stuck or want\n"
  printf "    the cluster for something else.\n\n"
  printf "    It needs passwordless ssh to %s and root there. Killercoda has both.\n\n" "$NODE"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    1 first        nothing else can pass while the node is NotReady\n"
  printf "    3 and 4 → 5    a label cannot help while the node is cordoned or tainted\n"
  printf "    1 → 6          the kubelet has to be running to read a static pod manifest\n"
  printf "    12 last        the pod count changes as tasks 6, 7 and 8 place pods\n\n"
  printf "%s  THE THREE FAULTS IN TASK 1%s\n\n" "$BO" "$N"
  printf "    They surface one at a time, which is the point — each fix reveals the\n"
  printf "    next, exactly like the real exam's 'the cluster is broken again' tasks:\n\n"
  printf "      dead              the service is stopped        → start it\n"
  printf "      auto-restart      bad clientCAFile in config    → read journalctl\n"
  printf "      running, NotReady wrong API port in kubeconfig  → read journalctl again\n\n"
  printf "    %sIf the Killercoda session expires, run %s/setup5.sh again.%s\n\n" "$D" "$HERE" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 5 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %sworker node failure troubleshooting · node: %s%s\n\n" "$D" "$NODE" "$N"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   nodeinfo   ·   %s%s\n\n" \
      "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show)
    need_n "${2:-}" "$CQ"; show "$2" ;;
  grade)
    if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"
    else grade_all; fi ;;
  solve)
    need_n "${2:-}" "$CS"
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps)
    need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 5 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  nodeinfo|info) nodeinfo ;;
  restore)
    if [ -x "$EX5/restore.sh" ]; then bash "$EX5/restore.sh"
    else printf "\n  %sno restore script at %s/restore.sh — run setup5.sh first%s\n\n" "$R" "$EX5" "$N"; exit 1; fi ;;
  reset) bash "$HERE/setup5.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s (exam 5)\n" "$VERSION" ;;
  *)
    printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"
    usage; exit 1 ;;
esac
