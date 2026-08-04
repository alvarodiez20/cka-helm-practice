# Using it

Everything below assumes `source ~/cka-practice/activate.sh` has run. It is
appended to your `~/.bashrc` by the first seed, so new shells pick it up.

[← back to the README](../README.md)

---


### One command to remember

```bash
cka
```

That prints the dashboard: every exam grouped by CKA domain, what each covers,
and which one is
currently selected.

```

  cka-practice v2.0.0 — 11 exams, 100 points each, pass mark 66
  grouped by CKA domain, heaviest first

  30%  Troubleshooting
     5  nodes         Worker node failures: kubelet, taints, static pods   not seeded
     6  tshoot        General troubleshooting: control plane, pods, RBAC   not seeded

  25%  Cluster architecture, installation and configuration
  ▸  1  helm-core     Helm: install, rollback, values, packaging           not seeded
     2  helm-values   Helm: repos, values files, --atomic, subcharts       not seeded
     3  helm-oci      Helm: real charts, CRDs, OCI registries              not seeded
     8  cluster       etcd backup and restore, kubeadm, certificates       not seeded
    11  kustomize     Kustomize: overlays, patches, generators, apply -k   not seeded

  20%  Services and networking
     4  netpol        NetworkPolicy and network troubleshooting            not seeded
    10  gateway       Ingress, Gateway API, and CNI troubleshooting        not seeded

  15%  Workloads and scheduling
     9  workloads     Workloads and scheduling: rollouts, Jobs, affinity   not seeded

  10%  Storage
     7  storage       Storage: PV, PVC, StorageClass, StatefulSet volumes  not seeded

  selected: helm-core  (Helm: install, rollback, values, packaging)
  cka scores grades every exam — takes a couple of minutes.

  cka use <name>   switch     q N · grade · explain N · next
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
cka scores             # grade every exam and show every score (takes a couple of minutes)
```

**Tab completion** works on exam names, verbs and task numbers.

### Seeding and re-seeding an exam

Installing an exam and seeding it are different things. `bootstrap.sh` downloads
all of them, but seeds only the one you asked for (exam 1 by default). An exam that
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
have all eleven seeded at once.

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
| 11 | `kustomize` | Kustomize: overlays, patches, generators, `apply -k` |

> **Upgrading from an earlier version?** The old numbered commands — `exam6`,
> `q6 4`, `grade7`, `explain3 2` — all still work exactly as before. Nothing
> breaks mid-session; `cka` is simply a shorter way in.

### These are shell functions, not a REPL

`kubectl` and `helm` stay in the foreground, which is where the exam is actually
solved. If you would rather not touch your shell at all, every script works
directly:

```bash
./exams/exam7.sh q 3 · ./exams/exam7.sh grade · ./cka.sh use storage
```

---

## Showing it to someone else

`demo/record-demo.sh` records a scripted terminal walkthrough with
[asciinema](https://asciinema.org) and renders it to a GIF and an animated SVG.
It types the commands itself, so the recording is reproducible rather than a
function of how fast you type.

```bash
pip install asciinema
cargo install --git https://github.com/asciinema/agg

./demo/record-demo.sh              # the default tour
EXAM=kustomize ./demo/record-demo.sh
```

[demo/README.md](../demo/README.md) compares the output formats — GIF, SVG,
asciinema embed, MP4, screenshots — and which ones survive being posted
where.

---
