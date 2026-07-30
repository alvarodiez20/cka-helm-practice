# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versioning applies to the exam suite itself — the tasks, the graders and the
tooling. A MAJOR bump means existing answers or scripts may no longer behave the
same way; MINOR means new tasks or commands were added; PATCH means fixes only.

## [1.2.1] — 2026-07-30

### Fixed

Verified exam 4 end to end on a Killercoda CKA playground. The cluster runs
**Cilium**, so NetworkPolicy is genuinely enforced there and the probe in
`setup4.sh` correctly reported `ENFORCED`. Exam 4 scores 100/100 after these
fixes, and all 13 tasks correctly read ✘ on a freshly seeded cluster.

- `epcount` and `epport` crashed with `TypeError: 'NoneType' object is not
  iterable`. A Service whose selector matches nothing still gets an
  EndpointSlice — one with `"endpoints": null` — so `.get("endpoints", [])`
  returns `None` rather than the default, which is exactly the state task 9
  starts in. Every list access now uses `or []` and the helpers degrade to 0
  instead of printing a traceback into the middle of `netcheck`.
- `netcheck` now explains why the two `frontend/client` probes read *blocked*
  once task 5 is solved. Both ends of a connection are evaluated
  independently: task 5 denies egress for every pod in `frontend` except port
  53, so client cannot open the connection even after task 8 fixes web's
  ingress rule. Both policies are correct and both tasks score — but the
  probe output looked like a failure, so it now says so explicitly, and task
  8's walkthrough covers the interaction.

## [1.2.0] — 2026-07-30

Four exams, 52 tasks, 400 points. The suite is no longer Helm-only.

### Added

- **Exam 4** (`setup4.sh`, `exam4.sh`) — 13 tasks, 100 points, on NetworkPolicy
  and network troubleshooting. No Helm; pure `kubectl`. Eight policy-authoring
  tasks and five troubleshooting ones:
  - default-deny ingress, and the `policyTypes` trap that takes egress down with
    it;
  - a bare `podSelector` in `from` (same namespace) versus `namespaceSelector`,
    including the fact that **NetworkPolicy cannot name a namespace** — it
    matches labels, with `kubernetes.io/metadata.name` as the way round it;
  - **the AND/OR trap**: one `from` element carrying both a `namespaceSelector`
    and a `podSelector` means AND; two elements mean OR. They differ by a single
    dash and the OR version allows vastly more traffic. This is the task the
    exam is built around;
  - default-deny egress that keeps DNS alive, on **both** UDP/53 and TCP/53 —
    allowing only UDP leaves large responses hanging intermittently;
  - `ipBlock` with `except`, and why `except` must sit inside `cidr`;
  - port ranges with `endPort`;
  - debugging a policy that applies cleanly and matches nothing, because a label
    has a one-letter typo and selectors have no referential integrity;
  - a Service with no endpoints (selector vs *pod* labels), a Service with
    endpoints that refuses connections (`port` vs `targetPort`), a pod that
    cannot resolve anything (`dnsPolicy: None`, and why it is immutable),
    converting a Service to a fixed `NodePort`, and finally working out which
    policies apply to a given pod — where a policy is excluded either because
    its selector misses or because its direction is wrong.
- **`netcheck`** — drives real traffic between the seeded pods and prints what
  got through, plus DNS resolution and endpoint counts. Grading does not depend
  on it; it is there so you can watch a policy take effect.
- **CNI enforcement probing.** NetworkPolicy is only enforced if the CNI
  implements it: plain Flannel accepts every policy object and blocks nothing,
  so an exam that assumed enforcement would quietly teach the wrong thing.
  `setup4.sh` does not guess from the CNI's name — it creates two pods, proves
  they can talk, applies a deny-all, and retries. The verdict is recorded in
  `~/exam4/enforcement`, reported at setup time, and repeated by `netcheck`.
- `exam4`, `q4`, `grade4`, `explain4`, `solve4`, `netcheck`, `exam4help` and
  `exam4reset` in `activate.sh`, with Tab completion.
- `EXAM=4` in `bootstrap.sh`, which now fetches all four exams.

### Changed

- The policy graders parse JSON with `python3` instead of grepping, because the
  distinctions that decide correctness are structural rather than textual — one
  `from` element versus two cannot be seen with `grep`. Verified against
  fixtures for every task plus eight deliberately-wrong variants, each confirmed
  to score zero.
- `README.md` is reframed around four exams rather than three Helm exams, and
  documents the enforcement caveat prominently.

## [1.1.1] — 2026-07-30

### Fixed

Verified exam 3 end to end on a Killercoda CKA playground — Kubernetes v1.35.1
and **Helm 4.1.1**, which is what the current exam ships. Helm 4 promoted
several Helm 3 flags to defaults and then removed the flags, so passing them is
a hard error rather than a harmless no-op. Three places were affected:

- `helm list -a` no longer exists (Helm 4 lists every status by default). This
  broke `hfield()` — and therefore every release-based grader — and made task 9
  report a **false pass**, because the failing `-a` produced no output and the
  "release is absent" check trivially succeeded. Graders now probe the flag once
  and adapt, and task 9 additionally verifies the release Secret is gone, which
  is version-independent ground truth.
- `helm status --show-resources` no longer exists (resources are always
  included). Task 10's solution used it, so the answer file came out empty.
- Task 9 and 13 statements assumed Helm 3's hiding behaviour. Both now teach the
  status filters (`--pending`), which behave identically on 3 and 4.

Also in `setup3.sh`: the `pending-install` seeding worked all along, but its
verification used `helm list -a` and so reported failure; and killing the
background install leaked a raw `line 99: 6366 Killed` job notice into the setup
output, now suppressed with `set +m`.

Exam 3 scores 100/100 on Helm 4 after these fixes. Exams 1 and 2 use only flags
Helm 4 kept and needed no changes.

### Added

- `demo/out/cka-helm-practice-exam3.{cast,gif}` — the recording, made on a real
  Killercoda playground, and linked at the top of the README.
- `demo/README.md`: a paste-ready Killercoda block, including the two things that
  otherwise bite — `bootstrap.sh` does not fetch `record-demo.sh`, and Killercoda
  is x86_64 so it needs the `agg-x86_64-unknown-linux-gnu` build.

## [1.1.0] — 2026-07-30

Three exams, 39 tasks, 300 points total.

### Added

- **Exam 3** (`setup3.sh`, `exam3.sh`) — 13 new tasks, 100 points, built from
  the Helm work candidates actually report on the current CKA. Unlike exams 1
  and 2 it runs against **real public chart repositories and a real OCI
  registry**, so it needs internet access; `setup3.sh` checks for egress up
  front rather than letting every task fail silently. Covered ground:
  - the CRD flag family, which is where most Helm points are lost. Task 2
    renders Argo CD with no CRDs (`--skip-crds` has no effect on that chart —
    its CRDs live in `templates/`, so `--set crds.install=false` is the answer)
    and task 4 renders Traefik's CRDs, which `helm template` omits by default
    because they live in `crds/` and need `--include-crds`. The two tasks look
    identical and have opposite answers.
  - installing Argo CD while keeping its CRDs out of the cluster;
  - `helm show chart` for the chart-version / app-version distinction;
  - OCI registries: `helm install oci://…` with no repository, and
    `helm pull --untar --untardir`;
  - `--set-json` for storing a nested object in a single flag;
  - a release stuck in `pending-install`, which `helm list` hides until you
    pass `-a`;
  - `helm status --show-resources`, and `helm list -A -a` as a full inventory.

  Runs on its own namespaces (`argocd`, `demo`, `limbo`) and its own answers
  directory (`~/answers3`, `~/exam3`), so all three exams can be active on the
  same cluster at once.
- `exam3`, `q3`, `grade3`, `explain3`, `solve3`, `exam3help` and `exam3reset` in
  `activate.sh`, with Tab completion for task numbers.
- `EXAM=3` support in `bootstrap.sh`, which now fetches all three exams.
- **`demo/record-demo.sh`** — records a scripted terminal walkthrough with
  asciinema and renders it to a GIF (`agg`) and an animated SVG (`svg-term`).
  It types the commands itself at a fixed pace, so recordings are reproducible
  instead of depending on live typing. `--cast-only` and `--render-only` split
  recording (on the cluster host) from rendering (anywhere).
- `demo/README.md` — comparison of GIF, animated SVG, asciinema embed, MP4 and
  screenshots, with which ones survive GitHub and which survive LinkedIn, plus
  the size/readability trade-offs that matter in practice.

### Changed

- `README.md` documents the third exam, its chart sources, and its
  internet requirement; the requirements section now names Helm 3.10 as the
  floor, since `--set-json` was added there.
- `.gitignore` covers `answers2/`, `answers3/`, `exam3/`, `cka-helm2/` and the
  recorder's scratch files.

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

[1.2.1]: https://github.com/alvarodiez20/cka-helm-practice/releases/tag/v1.2.1
[1.2.0]: https://github.com/alvarodiez20/cka-helm-practice/releases/tag/v1.2.0
[1.1.1]: https://github.com/alvarodiez20/cka-helm-practice/releases/tag/v1.1.1
[1.1.0]: https://github.com/alvarodiez20/cka-helm-practice/releases/tag/v1.1.0
[1.0.0]: https://github.com/alvarodiez20/cka-helm-practice/releases/tag/v1.0.0
