# Security

## What this software does to a machine

Read this before running it anywhere you care about. None of it is hidden, but
it is unusual enough to be worth stating plainly.

**It is designed for disposable lab clusters.** Killercoda, kind, minikube,
k3s, a throwaway VM. Not a cluster anyone depends on, and not your laptop's
Docker Desktop cluster if you use that for work.

The install is `curl … | bash`, which downloads shell scripts from
`raw.githubusercontent.com` and runs them. Then:

| It does this | Where |
|---|---|
| Creates and **deletes** namespaces, and everything in them | your cluster |
| Writes to `~/answers*` and `~/exam*` | your home directory |
| Appends one `source` line to `~/.bashrc` | your home directory |
| Installs Helm if it is missing | via the official `get-helm-3` script |
| Starts `python3 -m http.server` on `127.0.0.1:8879` and `:8880` | localhost |
| **Stops and misconfigures the kubelet** on a worker node | over `ssh`, as root |
| **Stops `kube-scheduler`** by moving its static pod manifest | control plane |
| **Disables the CNI configuration** on a worker, taking it NotReady | over `ssh`, as root |
| Creates a Secret containing a literal password (`s3cr3t`) | exam 11, your cluster |

The last three are exams 5 (`nodes`), 6 (`tshoot`) and 10 (`gateway`). They
break the cluster **on purpose** — diagnosing a genuinely broken node is the
point — and they are never seeded without being asked for. Each backs up every
file it touches on the node and each has a restore command (`exam5restore`,
`exam6restore`, `exam10restore`).

`kube-apiserver` and `etcd` are deliberately never broken.

## What it does not do

- It sends nothing anywhere. There is no telemetry, no analytics, no
  phoning home, and no network egress at all except: fetching its own scripts
  from GitHub at install time, pulling container images, and — for exam 3 and
  exam 10 — public Helm chart repositories and the Gateway API CRDs.
- It reads no credentials beyond the kubeconfig `kubectl` is already using.
- It writes nothing outside `~/answers*`, `~/exam*`, one line in `~/.bashrc`,
  and the cluster namespaces each exam owns.

## If you would rather not pipe a URL into a shell

Reasonable. Clone it and read it first — it is all bash, and the scripts are
commented:

```bash
git clone https://github.com/alvarodiez20/cka-practice.git
cd cka-practice
less bootstrap.sh exams/setup1.sh
./exams/setup1.sh && source ./activate.sh
```

Every release is an annotated git tag whose message, the CHANGELOG entry and
the GitHub Release body are the same text — the release workflow refuses to
publish otherwise — so you can check what a version claims to contain against
what it does.

## Reporting a vulnerability

Open a [GitHub issue](https://github.com/alvarodiez20/cka-practice/issues) for
anything that is not itself exploitable by disclosure. For something that is,
use GitHub's **private vulnerability reporting** on the Security tab.

Two classes of report are especially welcome:

1. **Anything that touches a machine in a way this file does not describe.**
   The list above is meant to be exhaustive; if it is not, that is a bug.
2. **A grader that awards points it should not.** It is not a security
   vulnerability in the usual sense, but it is the failure this project takes
   most seriously — people use these scores to decide whether they are ready
   to sit a paid exam. See the grader audit in
   [CONTRIBUTING.md](CONTRIBUTING.md#graders-must-fail-closed).

There is no bounty, and there is no formal SLA — this is a personal project.
Reports get a response.

## Supported versions

The latest release only. Upgrading is re-running `bootstrap.sh`.
