# How it works

What each seed actually builds, and what it needs from the machine you run it
on.

[← back to the README](../README.md) · [the exams](exams.md)

---


`setup1.sh` and `setup2.sh` each:

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

`setup11.sh` uses no Helm and no network. It writes two plain manifests into
`~/exam11/base` and deliberately does **not** write a kustomization.yaml —
authoring that is task 1 — plus a `~/exam11/broken` directory holding a
kustomization with three stacked faults for task 12. It reads the kustomize
version vendored into your `kubectl` and warns if it predates v5, because
task 3 turns on a field that arrived there.

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

## Requirements

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

The Helm exams are tested on **Helm 3 and Helm 4**. Helm 4 turned several Helm 3
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
