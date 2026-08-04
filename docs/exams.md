# The exams

Eleven independent exams, thirteen tasks each, one hundred points apiece.
They can all be active on the same cluster at once — separate namespaces,
chart sources and answer directories.

[← back to the README](../README.md) · [using it](usage.md) ·
[troubleshooting](troubleshooting.md)

---

## Coverage against the published curriculum

`cka` shows the same grouping, so the dashboard and this table cannot drift.

| Domain | Weight | Exams |
|---|---|---|
| Troubleshooting | 30% | `nodes`, `tshoot` — and `netpol` and `gateway` in part |
| Cluster architecture, installation and configuration | 25% | `helm-core`, `helm-values`, `helm-oci`, `kustomize`, `cluster` |
| Services and networking | 20% | `netpol`, `gateway` |
| Workloads and scheduling | 15% | `workloads` |
| Storage | 10% | `storage` |

`kustomize` and the three Helm exams both sit under Cluster Architecture
because the curriculum names them there together: *"use Helm and Kustomize to
install cluster components"* is one competency, not two.

**What each one needs:**

| Exam | Internet | Notes |
|---|---|---|
| `helm-core`, `helm-values` | no | charts are served from `localhost` |
| `helm-oci` | **yes** | real public repos and an OCI registry |
| `netpol`, `tshoot`, `storage`, `workloads` | images only | plain `kubectl` |
| `kustomize` | images only | plain `kubectl`; needs kustomize v5 (kubectl 1.27+) for task 3 |
| `nodes` | images only | **two nodes + passwordless ssh to the worker** |
| `cluster` | no | **must run on the control plane node** |
| `gateway` | **yes**, once | **two nodes + passwordless ssh**; fetches the Gateway API CRDs |

> ### ⚠️ Three exams break your cluster on purpose
>
> `nodes` stops the kubelet on a worker and corrupts its configuration.
> `tshoot` takes `kube-scheduler` down. `gateway` disables the CNI
> configuration on a worker, so the node goes NotReady and no new pod can be
> created there. All three back up every file they touch and all three have a
> restore command — `exam5restore`, `exam6restore`, `exam10restore` — but do not
> point any of them at a cluster you care about.
>
> Neither breaks `kube-apiserver` or `etcd`: that would take `kubectl` down and
> the grader with it. Where those failures matter, the walkthroughs cover what
> you would do with `crictl` and `/var/log/pods` instead.

### Exam 1 — the core workflow

Releases, revisions, values and packaging. Seeded by `setup1.sh`.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 7 | Install into a namespace that does not exist | `--create-namespace`, `--version`, `--set` |
| 2 | 8 | Recover a release broken by a bad upgrade | `helm history`, `helm rollback` |
| 3 | 6 | Find a release whose namespace is unknown | `helm list -A` |
| 4 | 7 | Upgrade without losing configured values | `--reuse-values` |
| 5 | 8 | Render manifests without installing | `helm template` |
| 6 | 7 | Dump all values, defaults included | `helm get values -a` |
| 7 | 7 | Uninstall but keep the release recoverable | `--keep-history` |
| 8 | 8 | Bring that release back from history | `helm rollback` on an uninstalled release |
| 9 | 10 | Create a chart with given chart/app versions | `helm create`, `helm lint` |
| 10 | 7 | Package a chart into a directory | `helm package -d` |
| 11 | 8 | Install a packaged chart, wait for readiness | `.tgz` install, `--wait` |
| 12 | 9 | Store an image tag as a string, not a number | `--set-string` |
| 13 | 8 | Declare and vendor a chart dependency | `helm dependency update` |

### Exam 2 — repos, values files and debugging

Seeded by `setup2.sh`.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 6 | Register a chart repo and refresh the cache | `helm repo add` / `update` |
| 2 | 6 | Capture a chart's default values | `helm show values` |
| 3 | 8 | Install from a values file you author | `-f` / `--values` |
| 4 | 8 | Two values files, in the order that wins | `-f` precedence |
| 5 | 7 | Deploy with one command that is safe to re-run | `helm upgrade --install` |
| 6 | 7 | Dump what a live release actually consists of | `helm get manifest` |
| 7 | 8 | Recover the values from a past revision | `helm get values --revision` |
| 8 | 9 | Make a failing upgrade undo itself | `--atomic` |
| 9 | 10 | Fix a chart until `helm lint` passes | cascading errors, fix and re-lint |
| 10 | 7 | Render one template and nothing else | `--show-only` |
| 11 | 8 | Find the failed release, wherever it is | `helm list -A --failed` |
| 12 | 9 | Set a subchart's value from the parent | `--set <subchart>.<key>` |
| 13 | 7 | Purge a release, history included | plain `helm uninstall` |

### Exam 3 — real charts, CRDs and OCI registries

Seeded by `setup3.sh`. **Needs internet access.** Nothing is pre-configured:
registering the repositories is part of the exam, as it is in the real one.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 6 | Register the Argo chart repo and cache its index | `helm repo add` / `update` |
| 2 | 9 | Render Argo CD with no CRDs in the output | `--skip-crds` does nothing here |
| 3 | 8 | Install Argo CD, keeping its CRDs out of the cluster | `--set crds.install=false` |
| 4 | 7 | Render a chart's CRDs, which are missing by default | `--include-crds` |
| 5 | 6 | Report the app version a chart version ships | `helm show chart` |
| 6 | 8 | Install from a values file you author | `-f`, nested keys |
| 7 | 8 | Install the same chart from an OCI registry | `oci://`, no repo |
| 8 | 8 | Change chart version, keep the configured values | `--reuse-values` |
| 9 | 8 | Find a release `helm list` refuses to show | `helm list -A -a`, pending-install |
| 10 | 8 | Report what Helm thinks the release consists of | `helm status --show-resources` |
| 11 | 8 | Store a nested object in one flag | `--set-json` |
| 12 | 9 | Fetch a chart from OCI, unpacked, without installing | `helm pull --untar --untardir` |
| 13 | 7 | Inventory every release, every namespace, every state | `helm list -A -a` |

Tasks 2 and 4 are the pair worth doing carefully. They look like the same
question and have opposite answers, because one chart keeps its CRDs in
`crds/` and the other keeps them in `templates/`. Getting that wrong is the
most commonly reported Helm mistake on the exam.

### Exam 4 — NetworkPolicy and network troubleshooting

Seeded by `setup4.sh`. No Helm; pure `kubectl`.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 6 | Default-deny ingress for a whole namespace | `podSelector: {}`, `policyTypes` |
| 2 | 7 | Allow one pod label on one port, same namespace | bare `podSelector` in `from` |
| 3 | 8 | Allow every pod in a labelled namespace | `namespaceSelector`; you cannot name a namespace |
| 4 | 9 | Allow only pods that match a pod AND a namespace label | **the AND/OR dash trap** |
| 5 | 9 | Default-deny egress without breaking DNS | UDP *and* TCP on 53 |
| 6 | 8 | Egress to a CIDR with a hole in it | `ipBlock` + `except` |
| 7 | 8 | Allow a whole port range | `endPort` |
| 8 | 8 | Fix a policy that applies but matches nothing | label typo, no referential integrity |
| 9 | 7 | A Service with no endpoints | selector must match *pod* labels |
| 10 | 7 | A Service with endpoints that refuses connections | `port` vs `targetPort` |
| 11 | 8 | A pod that cannot resolve anything | `dnsPolicy`, and why it is immutable |
| 12 | 7 | Expose a Service on a fixed port on every node | `NodePort`, allowed range |
| 13 | 8 | Work out which policies apply to one pod | selector match **and** direction |

Task 4 is the one to slow down on. These two differ by a single dash, and one
of them allows vastly more traffic than intended:

```yaml
from:                          from:
  - namespaceSelector:           - namespaceSelector:
      matchLabels:                   matchLabels:
        tier: backend                  tier: backend
    podSelector:                 - podSelector:
      matchLabels:                   matchLabels:
        app: api                       app: api
#  ^ one element = AND         #  ^ two elements = OR
```

**A warning that matters more than any task here.** NetworkPolicy is only
enforced if your CNI implements it. Plain Flannel, and any cluster with no
policy controller, will accept every policy object and silently block nothing —
`kubectl apply` succeeds and traffic flows regardless. `setup4.sh` probes this
directly: it applies a deny-all and tries a real connection. It tells you the
answer and records it, and `netcheck` repeats the warning. Grading reads the
policy objects you wrote, so the exam still works either way — but if you want
to *see* policies bite, you need Calico or Cilium.

Good news for the quick start: the **Killercoda CKA playground runs Cilium**, so
policies are enforced there and `netcheck` is meaningful. Verified on
Kubernetes v1.35.1.

One result surprises everyone once. After you solve task 5, `netcheck` will show
`frontend/client -> frontend/web` as **blocked** even though task 8 fixed web's
ingress rule — because task 5 denies egress for every pod in `frontend` except
port 53, and *both* ends of a connection have to allow it. Both policies are
correct and both tasks score. `netcheck` points this out when it sees task 5 in
place.

### Exam 5 — worker node failures

Seeded by `setup5.sh`. **Needs two nodes and passwordless ssh to the worker**,
because it breaks that node's kubelet on purpose. Killercoda has both.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 14 | Node is NotReady — three stacked faults | `systemctl status` → `journalctl` → repeat |
| 2 | 6 | Make the kubelet survive a reboot | `is-active` vs `is-enabled` |
| 3 | 7 | Ready but nothing schedules | `uncordon`; cordon vs drain |
| 4 | 8 | Remove a leftover NoSchedule taint | `kubectl taint node <n> key-` |
| 5 | 8 | Pending pod wants a label the node lacks | fix the **node**, not the Deployment |
| 6 | 10 | Run a static pod on the node | `staticPodPath` is unset — set it *and* write the manifest |
| 7 | 8 | DaemonSet skips the control plane | tolerate the taint, don't remove it |
| 8 | 8 | Pod requests more CPU than exists | requests vs allocatable |
| 9 | 6 | Record why the scheduler refused | `FailedScheduling` events |
| 10 | 7 | Report runtime and kubelet version | `.status.nodeInfo` |
| 11 | 6 | Report the kubelet's `clusterDNS` | read it on the node, not from the Service |
| 12 | 6 | Count pods assigned to the node | `--field-selector spec.nodeName=` |
| 13 | 6 | Which file tells the kubelet its config | `systemctl cat kubelet` |

Task 1 is the exam. It carries three faults that surface **one at a time**, so
each fix reveals the next — which is exactly how the real exam's "the cluster is
broken again" tasks behave:

| `systemctl status kubelet` says | the actual fault |
|---|---|
| `inactive (dead)` | the service is stopped — start it |
| `activating (auto-restart)` | `clientCAFile` points at a file that does not exist |
| `active (running)`, node still NotReady | kubeconfig points at port **6553**, not 6443 |

The habit it drills: `systemctl status` to see *how* it is failing,
`systemctl cat kubelet` to find *which files* it reads, `journalctl -u kubelet`
to hear it say what is wrong. Then re-check `kubectl get nodes` — two of the
three faults leave the service looking healthy from some angle.

**This exam breaks a real node.** Both files it edits are backed up on the node
first, and `exam5restore` puts everything back and waits for `Ready`. There is
deliberately no `drain` task: draining would evict the pods tasks 5–8 are graded
on, so a full `grade5` afterwards would fail work you had already done correctly.
Cordon-versus-drain is covered in task 3's walkthrough instead.

### Exam 6 — general troubleshooting

Seeded by `setup6.sh`. Troubleshooting is **30% of the CKA**, the
highest-weighted domain. Exam 4 covers networking and exam 5 covers nodes; this
one covers the rest.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 12 | Nothing schedules, and the pod has *no events* | kube-scheduler static pod manifest |
| 2 | 8 | Container killed the instant it starts | `OOMKilled`, exit **137** |
| 3 | 6 | Read why a dead container died | `logs --previous` + exit code |
| 4 | 8 | Container never starts at all | `ImagePullBackOff` |
| 5 | 8 | Stuck at `CreateContainerConfigError` | a missing ConfigMap |
| 6 | 8 | Healthy app, killed every few seconds | a liveness probe on the wrong port |
| 7 | 8 | Stuck at `Init:0/1` | `logs -c <init-container>` |
| 8 | 8 | A ServiceAccount needs exactly two verbs | Role + RoleBinding, `auth can-i --as` |
| 9 | 8 | A PVC that will not bind | `storageClassName` mismatch |
| 10 | 7 | Replicas that are never even created | a ResourceQuota, at admission |
| 11 | 6 | Which pod restarts most | `--sort-by` on a JSONPath |
| 12 | 6 | Every Warning, oldest first | event field selectors |
| 13 | 7 | An object that will not delete | finalizers |

**Do task 1 first.** `kube-scheduler` is down, so nothing new can be placed —
every other fix you make will look like it failed, because the corrected
Deployment creates a pod that then sits `Pending` for ever.

Task 1 turns on one distinction worth carrying into the exam:

| Symptom | What it means |
|---|---|
| `Pending` **with** events | the scheduler looked at your pod and refused it — taints, resources, affinity |
| `Pending` **with no events at all** | nobody looked. There is no scheduler running to produce one. |

**What is deliberately not broken:** `kube-apiserver` and `etcd`. Breaking
either takes `kubectl` down and the grader with it. Task 1's walkthrough covers
what you would do with `crictl` and `/var/log/pods` if the API server itself were
gone — which is the real answer on the exam, and untestable here.

### Exam 7 — storage

Seeded by `setup7.sh`. Storage is 10% of the CKA. Everything here is a static
hostPath PV, so **no dynamic provisioner is required** — it works on any cluster.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 7 | Create a PV to spec | capacity, accessModes, reclaim policy |
| 2 | 8 | A claim that will never bind | the five fields binding compares |
| 3 | 9 | A PV stuck in **Released** | a stale `claimRef` |
| 4 | 8 | Create a StorageClass | `WaitForFirstConsumer`, `allowVolumeExpansion` |
| 5 | 7 | Make it the cluster default | it is an annotation, not a field |
| 6 | 9 | Claim it and mount it in a pod | `volumes` + `volumeMounts` |
| 7 | 8 | List every PV with a given reclaim policy | JSONPath filters |
| 8 | 8 | Two containers sharing scratch space | `emptyDir` |
| 9 | 9 | A StatefulSet with per-replica volumes | `volumeClaimTemplates` |
| 10 | 8 | Drop one file into a directory | `subPath` |
| 11 | 7 | Which PV is a claim bound to | `volumeName` vs `claimRef` |
| 12 | 7 | A PVC that will not delete | `pvc-protection` |
| 13 | 5 | Report an access mode in short form | RWO / ROX / RWX |

**Task 3 is the one to slow down on.** A `Retain` PV whose claim was deleted goes
to `Released` and will *never* rebind, however correct the next claim is, because
`.spec.claimRef` still points at a claim that no longer exists. It looks
Available at a glance and behaves as though it is not.

Task 12 is the mirror image of exam 6's finalizer task, and the contrast is the
lesson: there the controller was gone and you cleared the finalizer by hand; here
`pvc-protection` is doing its job, so you remove the *reason* — delete the pod —
and the controller clears it for you.

### Exam 8 — etcd, kubeadm and certificates

Seeded by `setup8.sh`. **Run it on the control plane node.** Unlike exams 5 and 6
this one breaks nothing — every task is an operation you carry out.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 10 | Snapshot etcd | `etcdctl snapshot save` with mutual TLS |
| 2 | 7 | Report the snapshot's revision | `snapshot status`, and why it matters |
| 3 | 10 | Restore it into a new data dir | `etcdutl snapshot restore --data-dir` |
| 4 | 7 | Find etcd's `--data-dir` | reading a static pod manifest |
| 5 | 7 | Back up the etcd PKI | a snapshot alone is not a backup |
| 6 | 8 | Which certificate expires soonest | leaves last a year, CAs ten |
| 7 | 8 | Renew a certificate | `kubeadm certs renew` — and the restart it needs |
| 8 | 8 | Drain a node for maintenance | `--ignore-daemonsets`, the eviction API |
| 9 | 6 | Return it to service | `uncordon` moves nothing back |
| 10 | 8 | What could this cluster upgrade to | `kubeadm upgrade plan`, one minor at a time |
| 11 | 8 | Produce a working join command | `kubeadm token create --print-join-command` |
| 12 | 6 | Name the four control plane manifests | static pods are files, not API objects |
| 13 | 7 | Find the API server's advertise address | and why it breaks a migrated cluster |

**Why task 3 restores into a new directory.** A real etcd restore replaces
`/var/lib/etcd` with the API server stopped — that would take `kubectl` down and
the grader with it, exactly like breaking the API server in exam 6. So task 3
does the first half, which is what the exam usually asks for, and its walkthrough
gives the cutover in full.

This is also where `drain` finally lives. It was deliberately kept out of exam 5,
where evicting pods would have failed tasks that had already been graded; exam 8
has no pod-based state, so the drain/uncordon pair is safe here. Task 8 is graded
on the *eviction*, which survives the uncordon, so tasks 8 and 9 can both pass.

### Exam 9 — workloads and scheduling

Seeded by `setup9.sh`. The last domain to get an exam of its own. Nothing is
broken except one deliberately-bad rollout.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 8 | Undo a rollout to a broken image | `rollout undo`, not `set image` |
| 2 | 7 | Bound a rollout's disruption | `maxUnavailable` / `maxSurge` |
| 3 | 8 | A Job with a fixed completion count | `completions`, `parallelism`, `backoffLimit` |
| 4 | 8 | A suspended, non-overlapping CronJob | cron fields, `concurrencyPolicy` |
| 5 | 7 | Which revision is it on | the `deployment.kubernetes.io/revision` annotation |
| 6 | 8 | Autoscale on CPU | HPA needs requests *and* metrics-server |
| 7 | 8 | Never two replicas on one node | `podAntiAffinity`, `topologyKey` |
| 8 | 8 | Spread replicas evenly | `topologySpreadConstraints`, `maxSkew` |
| 9 | 8 | A priority class, and use it | preemption, `globalDefault` |
| 10 | 8 | Protect a Deployment from drains | PodDisruptionBudget |
| 11 | 7 | Stop killing a slow-starting app | `startupProbe` vs a long `initialDelaySeconds` |
| 12 | 7 | Scale, and cap the history | `revisionHistoryLimit` |
| 13 | 8 | Which pods are not Running | phase is coarser than you think |

Tasks 7 and 8 are deliberately paired, because the difference is the lesson:
anti-affinity is **binary** (never together, so 3 replicas on 2 nodes leaves one
Pending for ever), while a spread constraint **balances** (2/1 is fine). Almost
everyone reaches for anti-affinity when they want the second thing.

**Two things here look like failures and are not.** After task 7 one `api` pod
goes Pending — a hard anti-affinity caps replicas at the number of nodes, and
that is the rule working. And without metrics-server the HPA reports
`<unknown>/70%` and never scales; that is a missing add-on, not a broken object,
so task 6 is graded on the spec.

### Exam 10 — Ingress, the Gateway API, and the CNI

Seeded by `setup10.sh`. **Breaks pod networking on a worker.** Three sections in
one exam, because on a real cluster they are one problem: something has to
publish the service, something has to route to it, and something has to give the
pods addresses in the first place.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 6 | An IngressClass, and make it the default | `spec.controller` vs `metadata.name` |
| 2 | 9 | An Ingress with two paths | the backend port is the **service** port |
| 3 | 8 | Fix an Ingress written for an old cluster | the pre-1.18 class annotation, `pathType` |
| 4 | 8 | Serve it over TLS | `create secret tls`, and SNI matching the rule host |
| 5 | 8 | A route that 503s although the pods are healthy | a Service selector that matches nothing |
| 6 | 8 | A GatewayClass and a Gateway | the three-persona split, `allowedRoutes` |
| 7 | 9 | An HTTPRoute attached to it | `parentRefs`, and how silently it fails |
| 8 | 8 | Split 90/10 between two versions | weights are relative, and share one rule |
| 9 | 7 | Repair an orphaned HTTPRoute | a dangling parent is a valid object |
| 10 | 7 | Say why the node lost its network | `cni plugin not initialized`, and who reports it |
| 11 | 9 | Put the CNI configuration back | lexical order, `.disabled`, restart the *runtime* |
| 12 | 7 | Prove it by getting a pod an IP | Ready ≠ working; where the pod CIDR comes from |
| 13 | 6 | Make a CNI DaemonSet run everywhere | `operator: Exists`, `hostNetwork`, `system-node-critical` |

**No controller is installed, and that is deliberate.** There is no
ingress-nginx and nothing implements the GatewayClass, so Ingresses keep an
empty `ADDRESS` for ever and Gateways stay `PROGRAMMED=Unknown`. Every routing
task is graded on the object you wrote — which is exactly how the CKA grades
them. Chasing a missing address is the trap, not the task.

**Ingress and Gateway API side by side.** The same two hostnames are routed
twice, once each way, so the mapping is unavoidable: `ingressClassName` becomes
`parentRefs`, `pathType: Prefix` becomes `type: PathPrefix`, and the thing
Ingress could never express — a weighted split, a cross-namespace backend — is a
first-class field. The Gateway API entered the CKA curriculum in 2026 and the
questions reported so far are precisely this: attach a route, split traffic,
work out why a route does nothing.

**The CNI section is the destructive half.** Every file in `/etc/cni/net.d` is
renamed out of the way and an invalid config that sorts first is planted in
their place. The node goes NotReady and no new pod can start there — while every
pod already running carries on, because its network namespace was configured
before the fault. That asymmetry is the thing to recognise: a cluster in this
state looks healthy on a dashboard and cannot deploy anything.

Task 10 asks for the diagnosis and task 11 repairs it, in that order, because
repairing it erases the evidence. `exam10restore` puts the node back.

### Exam 11 — Kustomize

Seeded by `setup11.sh`. Nothing is broken except one deliberately unbuildable
kustomization. Kustomize is vendored into `kubectl` — there is no separate
binary to install, on this cluster or on the exam.

| # | Pts | Task | Key idea |
|---|---|---|---|
| 1 | 7 | Write a kustomization for two loose manifests | `resources`, and the file name it must have |
| 2 | 8 | Set the namespace and prefix every name | `namespace`, `namePrefix`, `apply -k` |
| 3 | 8 | Label everything without touching the selector | `labels` vs `commonLabels` — the immutable-selector trap |
| 4 | 8 | Change the image from the kustomization | `images:`, and what `name:` matches |
| 5 | 7 | Change the replica count the same way | `replicas:`, keyed on the **original** name |
| 6 | 9 | Generate a ConfigMap | `configMapGenerator`, and why the hash suffix exists |
| 7 | 7 | Generate one whose name must not change | per-generator `options` vs `generatorOptions` |
| 8 | 7 | Generate a Secret | `secretGenerator` — you give it plaintext |
| 9 | 9 | Build a prod overlay with a merge patch | `resources: ../../base`, strategic merge |
| 10 | 8 | Add an annotation with a JSON 6902 patch | `target` + op/path/value, and `~1` |
| 11 | 7 | Render the overlay without applying it | `kubectl kustomize` vs `apply -k` vs `--dry-run=server` |
| 12 | 8 | Fix a kustomization with three stacked faults | a field of the wrong shape, then the kind, then a missing path |
| 13 | 7 | Count what the overlay renders | `grep -c '^kind:'`, and why rendered ≠ in-cluster |

**The rule that makes this an exam.** Every transformation is graded on the
applied or rendered result **and** on the base manifests being untouched.
Editing `base/deployment.yaml` to change the image or the replica count
produces an identical cluster and scores zero — Kustomize exists so that the
base stays generic, and a grader that could not tell the difference would be
testing nothing.

**Task 3 is the one to slow down on**, and it is the one most likely to bite
on a real cluster. `commonLabels` adds your label to `spec.selector.matchLabels`
as well as to metadata. On a Deployment that is already applied that is fatal:

```
The Deployment "web-shop" is invalid: spec.selector: Invalid value: ...
field is immutable
```

`labels:` with `pairs:` never touches selectors, and `includeTemplates: true`
is what carries the label down into the pod template. Two spellings of the
same intent, one of which requires you to delete and recreate the Deployment.

**Task 12's three faults surface in build order, not file order** — the
`namePrefix` shape error hides both of the others, because the file has to
unmarshal before the kind can be checked or a path resolved. So "I fixed the
obvious thing and it still fails the same way" is the intended experience.

**Tasks 4 and 5 share a trap worth naming.** Both transformers match on the
resource's *original* identity — `shop`, not `web-shop` — because the rename
happens afterwards. Get it wrong and the render succeeds, changes nothing, and
warns about nothing.

### Task ordering

Some tasks depend on others. Each exam's `examhelp` spells its own out; the
short version:

| Exam | Dependency |
|---|---|
| `helm-core` | read task 8 before running task 7 |
| `helm-values` | task 1 registers the repo tasks 2, 3, 5, 8 and 10 need; task 13 destroys what 11 asks you to find |
| `helm-oci` | 1 → 2, 3; task 6 creates the namespace 7 and 8 use; do 9 before 13 |
| `netpol` | task 1's default-deny is what makes 2, 3 and 4 mean anything; leave 13 for last |
| `nodes` | **task 1 first** — nothing else can pass while the node is NotReady; 3 and 4 before 5; 12 last |
| `tshoot` | **task 1 first** — nothing new schedules while the scheduler is down; 5 before 10 |
| `storage` | 1 → 6; 4 → 5 |
| `cluster` | 1 → 2 → 3 is a chain; 8 → 9 are a pair |
| `workloads` | 1 before 5; 13 last |
| `gateway` | **10 before 11** — the repair erases the evidence; 11 before 12; 1 before 2 and 3; 6 before 7, 8 and 9 |
| `kustomize` | 1 before 2; 2 before 3–8, which are graded on the applied result; 9 before 10 and 11; 13 last |

`next` follows these automatically — it always hands you the lowest-numbered
unsolved task.

<details>
<summary>The original wording, for reference</summary>

**Order matters.** In exam 2, task 1 registers the repo that tasks 2, 3, 5, 8
and 10 install from, and task 13 destroys what task 11 asks you to find. In
exam 3, task 1 feeds 2 and 3, task 6 creates the namespace 7 and 8 use, and
task 9 must be done before 13. In exam 4, task 1's default-deny is what makes
tasks 2, 3 and 4 mean anything, and task 13 asks you to inventory policies you
created earlier — so leave it for last. In exam 5, nothing else can pass until
task 1 brings the node back, tasks 3 and 4 must both be done before task 5 can
schedule anything, and task 12's pod count moves as tasks 6–8 place pods, so
answer it last. In exam 6, task 1 gates everything, and task 10 asks you to scale
a Deployment that task 5 has to fix first. In exam 7, task 6's claim binds to the
PV task 1 creates, and you cannot default a StorageClass that does not exist yet.
In exam 8, tasks 1 → 2 → 3 are a chain, and 8 → 9 are a pair. In exam 9, task 1
must come before task 5 (the revision you report depends on the rollback), and
task 13 goes last because tasks 7 and 8 change what is Pending. `exam2help` …
`exam9help` spell out the dependencies. Exam 1 has one such pair: read task 8
before you run task 7.

</details>
