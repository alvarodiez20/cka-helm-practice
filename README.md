<div align="center">

# cka-helm-practice

**Ten hands-on CKA exams covering every domain of the curriculum. You solve them against a real cluster, and the grader inspects the cluster — not your answers.**

[![Version](https://img.shields.io/badge/version-1.10.0-blue?style=flat-square)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Exams](https://img.shields.io/badge/exams-10-orange?style=flat-square)](#the-ten-exams)
[![Tasks](https://img.shields.io/badge/tasks-130-orange?style=flat-square)](#the-ten-exams)
[![Pass mark](https://img.shields.io/badge/pass%20mark-66-brightgreen?style=flat-square)](#scoring)

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://www.cncf.io/training/certification/cka/)
[![Helm](https://img.shields.io/badge/Helm-3.x%20%7C%204.x-0F1689?style=flat-square&logo=helm&logoColor=white)](https://helm.sh)
[![Bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Killercoda](https://img.shields.io/badge/Killercoda-ready-1DB954?style=flat-square)](https://killercoda.com/playgrounds/scenario/cka)

[Install](#install) · [How to use it](#how-to-use-it) · [The ten exams](#the-ten-exams) · [Requirements](#requirements) · [Troubleshooting](#troubleshooting)

<!-- Recorded with demo/record-demo.sh on a Killercoda CKA playground
     (Kubernetes v1.35.1, Helm 4.1.1). See demo/README.md. -->
![Exam 3: the --skip-crds trap, then a full 100/100 graded against a live cluster](demo/out/cka-helm-practice-exam3.gif)

</div>

---

## What this is

Ten independent exams, thirteen tasks each, one hundred points apiece. Every
task is something you **do** to a live cluster. When you ask for a score, the
grader inspects the cluster's real state — release revisions, stored value
types, rendered manifests, endpoint addresses, certificate dates — and never
compares your answer against a stored one.

That distinction matters more than it sounds. `--set image.tag=1.25` and
`--set-string image.tag=1.25` produce identical-looking YAML and score
differently, because one stores a number. A NetworkPolicy with two `from`
elements instead of one applies cleanly and allows far more traffic than
intended, and scores zero. Guessing does not work here.

Every task also carries an `explain` walkthrough: what to inspect first, what
each flag actually does, how to verify, and the specific mistake that usually
costs the points.

---

## Install

Open the [Killercoda CKA playground](https://killercoda.com/playgrounds/scenario/cka)
— its Kubernetes version tracks the exam — and run:

```bash
curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-helm-practice/main/bootstrap.sh | bash
source ~/cka-helm-practice/activate.sh
```

That installs all ten exams and **seeds the first one**, which takes about a
minute. New shells pick the commands up automatically via `~/.bashrc`.

Installing and seeding are different things. All ten are installed; *seeding*
means building an exam's namespaces, workloads and deliberately broken objects
in the live cluster. Only one is seeded up front — doing all ten would take
several minutes and, for exams 5, 6 and 10, break the cluster before you had
asked it to. **You do not have to seed the rest yourself:** `cka use storage` notices
the exam is missing and builds it.

So `curl … | bash` is all you need. If you already know you want a different
exam, `EXAM` saves you building exam 1 first:

```bash
curl -sL .../bootstrap.sh | EXAM=7 bash         # seed storage instead
curl -sL .../bootstrap.sh | EXAM=none bash      # install, seed nothing
```

Or clone it:

```bash
git clone https://github.com/alvarodiez20/cka-helm-practice.git
cd cka-helm-practice && ./setup.sh && source ./activate.sh
```

---

## How to use it

### One command to remember

```bash
cka
```

That prints the dashboard: all ten exams, what each covers, and which one is
currently selected.

```
  cka-helm-practice v1.10.0 — ten exams, 100 points each, pass mark 66

       NAME          TOPIC                                                SCORE
  ▸ 1  helm-core     Helm: install, rollback, values, packaging           74/100
    2  helm-values   Helm: repos, values files, --atomic, subcharts        0/100
    3  helm-oci      Helm: real charts, CRDs, OCI registries               0/100
    4  netpol        NetworkPolicy and network troubleshooting             0/100
    ...
```

The `SCORE` column reads `not seeded` for any exam that does not exist in the
cluster yet. Plain `cka` works that out from one `kubectl get ns`, so it stays
instant; `cka scores` runs the graders, and skips the ones with nothing to
grade.

### Pick an exam, then work on it

```bash
cka use storage        # select it — by name, or by number: cka use 7
```

**Selecting an exam seeds it if it is not there.** You do not have to think
about which exams have been built:

```
$ cka use netpol

  selected netpol — NetworkPolicy and network troubleshooting
  q N · grade · explain N · next

  'netpol' is not seeded yet — building it now
  ...
```

Exams 5 (`nodes`), 6 (`tshoot`) and 10 (`gateway`) are the exception. Their seeds
break a worker node, `kube-scheduler` and a worker's CNI configuration on
purpose, so selecting them asks first rather than wrecking a cluster you were
using for something else. Answer `y`, or build them deliberately with `reset`.

From then on the verbs are **unnumbered** and act on whatever you selected:

| Command | What it does |
|---|---|
| `list` | every task, with its points and a ✔ if it already passes |
| `q 3` | show task 3 |
| `next` | jump straight to the first unsolved task |
| `grade` | grade everything and print the score out of 100 |
| `grade 3` | grade one task |
| `explain 3` | the full walkthrough, with the reasoning and the trap |
| `solve 3` | just the commands, no explanation |
| `info` | that exam's own dashboard — connectivity, node health, storage, whatever it has |
| `reset` | re-seed this exam from scratch |

A typical session looks like this:

```bash
cka use tshoot         # general troubleshooting
next                   # what should I do first?
# ... solve it against the cluster ...
grade 1                # did it work?
explain 1              # why didn't it?
grade                  # where am I overall?
```

### Working across exams

You do not have to select an exam to touch it. Put its name first:

```bash
cka storage q 3        # task 3 of the storage exam
cka 7 grade            # the same exam, by number
cka scores             # grade all ten and show every score (takes a minute)
```

**Tab completion** works on exam names, verbs and task numbers.

### Seeding and re-seeding an exam

Installing an exam and seeding it are different things. `bootstrap.sh` downloads
all ten, but seeds only the one you asked for (exam 1 by default). An exam that
is installed but not seeded has a task list and a grader, and nothing in the
cluster to point them at.

`cka use <name>` closes that gap for you — it seeds on selection. `reset`
rebuilds an exam you already have:

```bash
reset                  # re-seed the exam you have selected
cka netpol reset       # re-seed a specific one
exam4reset             # the same thing, by number
```

Re-seeding **deletes the exam's namespaces and everything in them**, then
recreates them. Anything you wrote lives in those namespaces, so a reset throws
your work away — that is the point of it, but it is not undoable.

It is not instant. Kubernetes deletes a namespace asynchronously, and pods
running `sleep` ignore `SIGTERM` and take their full 30-second grace period, so
a re-seed can spend a minute or two just waiting for the previous run to
disappear before it creates anything. **Let it finish.** If you interrupt it, or
run two seeds at once, you can end up with namespaces stuck mid-delete.

The seed will not lie to you about this. If a namespace cannot be created it
stops with `✘ could not create namespace ...` or `✘ namespace ... is stuck in
Terminating` and exits non-zero, rather than reporting success over a half-built
exam. If you see that, wait for the namespace to go and run the seed again:

```bash
kubectl get ns                     # look for anything Terminating
reset
```

Exams do not interfere with each other. Each one owns its own namespaces and its
own `~/answersN` directory, so seeding exam 7 never disturbs exam 4, and you can
have all ten seeded at once.

### The names

| # | Name | Covers |
|---|---|---|
| 1 | `helm-core` | Helm: install, rollback, values, packaging |
| 2 | `helm-values` | Helm: repos, values files, `--atomic`, subcharts |
| 3 | `helm-oci` | Helm: real charts, CRDs, OCI registries |
| 4 | `netpol` | NetworkPolicy and network troubleshooting |
| 5 | `nodes` | Worker node failures: kubelet, taints, static pods |
| 6 | `tshoot` | General troubleshooting: control plane, pods, RBAC |
| 7 | `storage` | Storage: PV, PVC, StorageClass, StatefulSet volumes |
| 8 | `cluster` | etcd backup and restore, kubeadm, certificates |
| 9 | `workloads` | Workloads and scheduling: rollouts, Jobs, affinity |
| 10 | `gateway` | Ingress, Gateway API, and CNI troubleshooting |

> **Upgrading from an earlier version?** The old numbered commands — `exam6`,
> `q6 4`, `grade7`, `explain3 2` — all still work exactly as before. Nothing
> breaks mid-session; `cka` is simply a shorter way in.

### These are shell functions, not a REPL

`kubectl` and `helm` stay in the foreground, which is where the exam is actually
solved. If you would rather not touch your shell at all, every script works
directly:

```bash
./exam7.sh q 3 · ./exam7.sh grade · ./cka.sh use storage
```

---

## Scoring

100 points per exam; **66 passes**, the real CKA mark. There is no partial
credit within a task — it satisfies every condition or it scores zero, which is
how the exam's own automated checks behave.

```
  SCORE: 74/100  (74%)   PASS
```

`list` shows a ✔ beside tasks that already pass, so you can leave and come back.
Grading is idempotent and reads live state, so it is always current.

---

## The ten exams

They are independent and can all be active on the same cluster at once —
separate namespaces, chart sources and answer directories.

**Coverage against the published curriculum:**

| Domain | Weight | Exams |
|---|---|---|
| Troubleshooting | 30% | `netpol`, `nodes`, `tshoot` |
| Cluster Architecture & Installation | 25% | `helm-core`, `helm-values`, `helm-oci`, `cluster` |
| Services & Networking | 20% | `netpol`, `gateway` |
| Workloads & Scheduling | 15% | `workloads` |
| Storage | 10% | `storage` |

**What each one needs:**

| Exam | Internet | Notes |
|---|---|---|
| `helm-core`, `helm-values` | no | charts are served from `localhost` |
| `helm-oci` | **yes** | real public repos and an OCI registry |
| `netpol`, `tshoot`, `storage`, `workloads` | images only | plain `kubectl` |
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

Releases, revisions, values and packaging. Seeded by `setup.sh`.

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

## Showing it to someone else

`demo/record-demo.sh` records a scripted terminal walkthrough with
[asciinema](https://asciinema.org) and renders it to a GIF and an animated SVG:

```bash
pip install asciinema
cargo install --git https://github.com/asciinema/agg

./demo/record-demo.sh            # exam 1
EXAM=3 ./demo/record-demo.sh     # exam 3
```

It types the commands itself, so the recording is reproducible.
[demo/README.md](demo/README.md) compares the formats — GIF, SVG, asciinema
embed, MP4, screenshots — and which ones survive being posted where.

## How it works

`setup.sh` and `setup2.sh` each:

1. check you have a reachable cluster, and install Helm if it is missing;
2. build a practice chart in three versions and serve it from a **local chart
   repository** on `127.0.0.1:8879` (exam 1) or `:8880` (exam 2), via
   `python3 -m http.server` — so the exams work with no internet access beyond
   the pod images;
3. seed the cluster into the state the tasks assume: a release with several
   revisions and a broken current one, a release hidden in an unobvious
   namespace, a genuinely failed release, a chart that fails `helm lint`, a
   parent chart with a vendored subchart.

`setup3.sh` works differently on purpose. There is no local repository — it
checks egress to the real chart sources, removes any repo the tasks ask you to
add, and seeds one release stuck in `pending-install` for task 9 (by starting a
real install and killing it, which is how that state happens in production).
The charts it uses:

| Alias | Source |
|---|---|
| `argo` | `https://argoproj.github.io/argo-helm` |
| `traefik` | `https://traefik.github.io/charts` |
| `ingress-nginx` | `https://kubernetes.github.io/ingress-nginx` |
| `podinfo` | `https://stefanprodan.github.io/podinfo` |
| `podinfo` (OCI) | `oci://ghcr.io/stefanprodan/charts/podinfo` |

Chart versions are pinned, and historical versions never leave a repo index, so
the tasks stay valid.

`setup4.sh` uses no Helm at all. It creates five labelled namespaces with pods
that serve and pods you can `exec` into, plants three broken Services and a
NetworkPolicy with a one-letter label typo, and then probes whether the CNI
enforces policy. Its layout is written to `~/exam4/README.txt` so you never have
to guess a label.

Answers are the cluster's own state. A few tasks want a file instead, and say so
— those live in `~/answers` … `~/answers4`. Charts and values files you author go
in `~/exam2` and `~/exam3`.

Exam 4 grades the NetworkPolicy tasks by parsing the policy objects with real
JSON rather than `grep`, because the distinctions that matter are structural: one
`from` element versus two, UDP versus TCP on port 53. An almost-right policy
scores zero. The troubleshooting tasks are graded on behaviour instead —
endpoints have to populate, the endpoint port has to be right, DNS has to
resolve.

### Requirements

- a real cluster and `kubectl` that can reach it (Killercoda, kind, minikube, k3s)
- for exams 5 and 10: **two nodes**, passwordless `ssh` to the worker, and root
  there. For exam 8: run it **on the control plane**, with `etcdctl`/`etcdutl`
  and `kubeadm` available — `setup8.sh` checks each and tells you what is
  missing rather than failing obscurely later. On a single-node cluster the only node is the control plane, and
  breaking that is a different exam; `setup5.sh` refuses rather than trying.
- `python3`, to serve the local chart repository (exams 1 and 2)
- `bash` 3.2 or newer
- Helm 3.10 or newer — installed automatically if absent
  (exam 3 task 11 uses `--set-json`, added in 3.10)
- internet access, for exam 3 and for exam 10's Gateway API CRDs

All three exams are tested on **Helm 3 and Helm 4**. Helm 4 turned several Helm 3
flags into defaults and then removed the flags, so passing them is now a hard
error rather than a no-op. Exam 3 teaches the differences where they come up, and
the graders detect which version you are on:

| Task | Helm 3 | Helm 4 |
|---|---|---|
| 9 | `helm list -a` to see pending releases | lists every status by default; `-a` removed |
| 10 | `helm status --show-resources` | resources always included; flag removed |
| 13 | `helm list -A -a` | `helm list -A` |

`--pending`, `--failed` and the other status filters work on both, which is why
the solutions prefer them.

## Troubleshooting

**`cka: command not found`** — the shell functions are not loaded. Run
`source ~/cka-helm-practice/activate.sh`. New shells pick it up automatically.

**`./exam.sh: No such file or directory`** — you are not in the repo directory.
Either `cd ~/cka-helm-practice`, or load the functions and forget about
directories.

**Every task suddenly shows ✘** — the Killercoda session expired and took the
cluster with it. Re-seed the selected exam with `reset`, or any of them with `cka <name> reset`.

**I selected an exam and none of its namespaces exist** — on 1.9.0 and later
this does not happen: `cka use <name>` seeds the exam if it is missing. Before
that, `bootstrap.sh` seeded only exam 1 and `cka use` never checked, so
selecting any other exam gave you a task list with nothing behind it and you had
to run `reset` by hand every session. Re-run `bootstrap.sh` to pick up the fix.

**A task refers to a pod or namespace that does not exist** — the seed did not
finish. Check what is actually there:

```bash
kubectl get ns
kubectl get pods -A
```

If a namespace the exam needs is missing or `Terminating`, wait for it to
disappear and run `reset` again. This is most likely if you re-seeded on top of
a previous run and interrupted it, or ran two seeds at the same time. See
[Seeding and re-seeding an exam](#seeding-and-re-seeding-an-exam).

> Versions before 1.8.2 could hit this on their own: the seed deleted the old
> namespaces without waiting long enough, then recreated them with all kubectl
> output discarded, so a failed create was invisible and the script still
> printed `✔`. Every seed now waits properly and exits non-zero instead. If you
> installed before then, re-run `bootstrap.sh` to pick up the fix.

**The seed stops with `namespace ... is stuck in Terminating`** — something in
that namespace has a finalizer that is not completing. The seed already tries to
clear it. If it still will not go, find what is holding it:

```bash
kubectl get ns <name> -o jsonpath='{.spec.finalizers}{"\n"}'
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n1 kubectl get -n <name> --ignore-not-found 2>/dev/null
```

On a lab cluster the blunt fix is to drop the finalizers and re-seed:

```bash
kubectl get ns <name> -o json \
  | tr -d '\n' | sed 's/"finalizers": *\[[^]]*\]/"finalizers": []/' \
  | kubectl replace --raw "/api/v1/namespaces/<name>/finalize" -f -
```

**Exam 4: my policies are all correct but nothing is ever blocked** — your CNI
does not enforce NetworkPolicy. `netcheck` says so explicitly. Grading is
unaffected; seeing traffic actually denied needs Calico or Cilium.

**Exam 5: `setup5.sh` says it cannot ssh to the node** — it has to stop the
kubelet and edit files there, which needs passwordless ssh and root. On
Killercoda `ssh node01` works out of the box. If your worker has another name,
set `CKA_NODE=<name>`.

**Exam 5: I have wrecked the node and want out** — `exam5restore` copies the
pristine `config.yaml` and `kubelet.conf` back from the node's backup directory,
re-enables and restarts the kubelet, clears the taint and cordon, and waits for
`Ready`.

**Exam 6: I fixed a Deployment and the pod still will not start** — task 1.
While `kube-scheduler` is down nothing new can be placed, so a correct fix still
leaves you with a `Pending` pod. Also mind the CrashLoopBackOff backoff: it grows
to 5 minutes, so a fixed pod can take minutes to retry. `kubectl delete pod` skips
the wait.

**Exam 4: a task scores zero and the YAML looks right** — for the policy tasks,
`kubectl get netpol <name> -o yaml` and compare the *structure*, not the text.
Count the dashes under `from:`; one element means AND, two mean OR. `explain N`
ends with the exact distinction the grader makes.

**Exam 10: tasks 6 to 9 score zero and `kubectl get gateway` says the resource
does not exist** — the Gateway API is not part of Kubernetes. It ships as CRDs
on its own release schedule, and `setup10.sh` installs them for you if it can
reach GitHub. If it could not, install them by hand and re-grade:

```bash
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
```

**Exam 10: my Ingress never gets an ADDRESS and my Gateway is never Programmed**
— nothing is installed to give them one, on purpose. Both are graded on the
object you wrote, as they are on the real exam.

**Exam 10: I want the broken node back** — `exam10restore` removes the planted
config, un-disables the real ones, restarts the container runtime and waits for
`Ready`. If the node is still NotReady afterwards, check that nothing is left:
`ssh node01 ls -l /etc/cni/net.d`.

**Task 1 of exam 2 fails after a session restart** — the local chart repo server
died. `exam2reset` restarts it.

**`setup3.sh` says it cannot reach the chart repositories** — exam 3 installs
from the real internet by design. If the environment is offline, use exam 1 or
exam 2, which serve their charts from `localhost`.

**Exam 3 task 11 always scores zero** — `--set-json` needs Helm 3.10+. Check
`helm version`.

**A task scores zero and you are sure it is right** — run `grade N` on its own,
then work through `explain N`; each walkthrough ends with the exact verification
commands the grader uses.

## Versioning

The exam suite is versioned with [semantic versioning](https://semver.org): MAJOR
if existing answers or scripts may behave differently, MINOR for new tasks or
commands, PATCH for fixes. See [CHANGELOG.md](CHANGELOG.md), or ask:

```bash
exam version
```

## License

[MIT](LICENSE) — use it, fork it, add your own tasks.

---

<div align="center">
<sub>Not affiliated with the CNCF or the Linux Foundation. Good luck with the exam.</sub>
</div>
