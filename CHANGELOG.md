# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versioning applies to the exam suite itself — the tasks, the graders and the
tooling. A MAJOR bump means existing answers or scripts may no longer behave the
same way; MINOR means new tasks or commands were added; PATCH means fixes only.

## [1.0.0] — 2026-07-29

First tagged release. Two independent exams, 26 tasks, 200 points total.

### Added

- **Exam 2** (`setup2.sh`, `exam2.sh`) — 13 new tasks, 100 points, covering
  ground exam 1 does not: repository management, `helm show`, values files and
  `-f` precedence, `upgrade --install`, `get manifest`, `get values --revision`,
  `--atomic` auto-rollback, chart debugging with `helm lint`,
  `template --show-only`, status filters, subchart value overrides, and full
  history purge. Runs on its own chart repo (port 8880), namespaces and answers
  directory, so both exams can be active on the same cluster at once.
- `explain N` — step-by-step walkthrough for every task in both exams: what to
  inspect before touching the cluster, what each flag does and why, how to
  verify, and the trap that most commonly costs the points.
- `help` — a real usage screen, including the task ordering constraints.
- `activate.sh` — shell functions (`exam`, `q`, `grade`, `explain`, `solve` and
  their `2`-suffixed counterparts) so the exams are usable from any directory
  without the `./exam.sh` prefix, with Tab completion for task numbers.
  Deliberately not a REPL: `kubectl` and `helm` stay in the foreground, which is
  where the exam is actually solved.
- `VERSION`, `CHANGELOG.md` and a `version` subcommand on both exams.
- `EXAM=2` support in `bootstrap.sh`, which now fetches both exams.

### Changed

- All task statements, solutions and interface text are in **English**, matching
  the real CKA. Setup output and this repo's docs are English too.
- Task numbers are validated before use, so `q 99` or `grade abc` report the
  problem and exit 1 instead of dereferencing a missing array entry.
- Unknown subcommands print the usage screen and exit 1.
- Dropped `declare -A` in favour of plain indexed arrays — every key is an
  integer, so the scripts now run on bash 3.2 as well as bash 5.
- `setup.sh` prints the `cd` step and wires `activate.sh` into `~/.bashrc`.
  Previously it told you to run `./exam.sh` from a directory your shell was
  never in, because `bootstrap.sh` does its `cd` inside the `curl | bash`
  subshell.
- The seeded broken image tag is `does-not-exist-tag` rather than Spanish.

## [0.1.0] — 2026-07-29

Initial version, unreleased.

### Added

- **Exam 1** (`setup.sh`, `exam.sh`) — 13 tasks, 100 points, covering install
  with `--create-namespace` and pinned versions, rollback from history, finding
  a release cluster-wide, `--reuse-values`, `helm template`, `get values -a`,
  `uninstall --keep-history` and recovery, `helm create` and `lint`,
  `helm package`, installing a packaged chart with `--wait`, `--set-string`, and
  chart dependencies.
- `bootstrap.sh` — one-line install for Killercoda.
- A local chart repository served on `127.0.0.1:8879`, so the exam works with no
  internet access beyond the pod images.

[1.0.0]: https://github.com/alvarodiez20/cka-helm-practice/releases/tag/v1.0.0
