<div align="center">

# cka-helm-practice

**Two hands-on Helm exams for the CKA. You solve them against a real cluster, and the grader checks the cluster — not your answers.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Tasks](https://img.shields.io/badge/tasks-26-orange?style=flat-square)](#the-two-exams)
[![Points](https://img.shields.io/badge/points-200-orange?style=flat-square)](#scoring)
[![Pass mark](https://img.shields.io/badge/pass%20mark-66-brightgreen?style=flat-square)](#scoring)

[![Helm](https://img.shields.io/badge/Helm-3.x%20%7C%204.x-0F1689?style=flat-square&logo=helm&logoColor=white)](https://helm.sh)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-CKA-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://www.cncf.io/training/certification/cka/)
[![Bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Killercoda](https://img.shields.io/badge/Killercoda-ready-1DB954?style=flat-square)](https://killercoda.com/playgrounds/scenario/cka)
[![Offline](https://img.shields.io/badge/works-offline-lightgrey?style=flat-square)](#how-it-works)

[![Last commit](https://img.shields.io/github/last-commit/alvarodiez20/cka-helm-practice?style=flat-square)](https://github.com/alvarodiez20/cka-helm-practice/commits/main)
[![Repo size](https://img.shields.io/github/repo-size/alvarodiez20/cka-helm-practice?style=flat-square)](https://github.com/alvarodiez20/cka-helm-practice)

[Quick start](#quick-start) · [Commands](#commands) · [The two exams](#the-two-exams) · [Scoring](#scoring) · [Troubleshooting](#troubleshooting)

</div>

---

These are not theory questions. Each task is something you do to a live cluster,
and `grade` inspects the real state afterwards — release status, revision
numbers, stored values, rendered manifests, whether a chart passes `helm lint`.
Guessing does not score.

Task statements are in **English**, like the real exam. Every task has an
`explain` walkthrough that shows what to inspect first, what each flag does and
why, how to verify, and the trap that usually costs the points.

## Quick start

Open the [Killercoda CKA playground](https://killercoda.com/playgrounds/scenario/cka)
— its Kubernetes version matches the exam — and paste:

```bash
curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-helm-practice/main/bootstrap.sh | bash
```

That downloads both exams and seeds exam 1. To seed exam 2 instead:

```bash
curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-helm-practice/main/bootstrap.sh | EXAM=2 bash
```

Or clone it:

```bash
git clone https://github.com/alvarodiez20/cka-helm-practice.git
cd cka-helm-practice && ./setup.sh
```

Then load the shell functions once — new shells pick them up automatically via
`~/.bashrc`:

```bash
source ~/cka-helm-practice/activate.sh
```

## Commands

From any directory, once `activate.sh` is loaded:

| Exam 1 | Exam 2 | What it does |
|---|---|---|
| `exam` | `exam2` | list every task with points and ✔/✘ status |
| `q N` | `q2 N` | show task N |
| `grade` | `grade2` | grade everything, print the score out of 100 |
| `grade N` | `grade2 N` | grade one task |
| `explain N` | `explain2 N` | step-by-step walkthrough, with the reasoning |
| `solve N` | `solve2 N` | just the commands, no explanation |
| `examhelp` | `exam2help` | full usage, including task ordering |
| `examreset` | `exam2reset` | re-seed that exam from scratch |

`q`, `grade`, `explain` and `solve` complete task numbers with **Tab**.

These are shell functions, not a REPL: `kubectl` and `helm` stay in the
foreground, which is where the exam is actually solved. If you would rather not
touch your shell, everything works through the scripts directly — `./exam.sh`,
`./exam.sh q 4`, `./exam2.sh explain 8`, `./exam.sh help`.

## The two exams

They are independent, cover different ground, and can both be active on the same
cluster at once — separate chart repos, namespaces and answer directories.

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

**Order matters** in exam 2: task 1 registers the repo that tasks 2, 3, 5, 8 and
10 install from, and task 13 destroys what task 11 asks you to find. `exam2help`
spells out the dependencies. Exam 1 has one such pair: read task 8 before you
run task 7.

## Scoring

100 points per exam, and **66 passes** — the real CKA pass mark. Partial credit
does not exist per task: a task either satisfies every condition or scores zero,
which is also how the real exam's automated checks behave.

```
  SCORE: 74/100  (74%)   PASS
```

`exam` and `exam2` show a ✔ next to tasks that already pass, so you can leave and
come back.

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

Answers are the cluster's own state. A few tasks want a file instead, and say so
— those live in `~/answers` (exam 1) and `~/answers2` (exam 2). Working charts
and values files for exam 2 are in `~/exam2`.

### Requirements

- a real cluster and `kubectl` that can reach it (Killercoda, kind, minikube, k3s)
- `python3`, to serve the local chart repository
- `bash` 3.2 or newer
- Helm 3 or 4 — installed automatically if absent

## Troubleshooting

**`./exam.sh: No such file or directory`** — you are not in the repo directory.
Either `cd ~/cka-helm-practice`, or load the functions and forget about
directories: `source ~/cka-helm-practice/activate.sh`.

**Every task suddenly shows ✘** — the Killercoda session expired and took the
cluster with it. Re-seed: `examreset` (or `exam2reset`).

**Task 1 of exam 2 fails after a session restart** — the local chart repo server
died. `exam2reset` restarts it.

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
