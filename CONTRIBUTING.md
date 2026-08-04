# Contributing

Thanks for looking. Fixes, new tasks and whole new exams are all welcome.

Before anything else: **there is one rule that is not negotiable**, and it is
in [Graders must fail closed](#graders-must-fail-closed) below. Everything else
here is convention.

---

## Run the checks first

All of CI runs locally and none of it needs a cluster. This takes about a
minute and catches almost everything a reviewer would:

```bash
git ls-files '*.sh' | xargs -n1 bash -n     # syntax
./scripts/audit-graders.sh                  # no grader awards free points
./scripts/check-tasks.sh                    # every task renders
./scripts/release.sh --check                # versions agree
shellcheck -S warning -e SC2086,SC2181,SC1090,SC1091,SC2034,SC2207,SC2046 \
  $(git ls-files '*.sh')
```

Testing against a real cluster is the other half, and there is no substitute
for it. A [Killercoda CKA playground](https://killercoda.com/playgrounds/scenario/cka)
is free and disposable:

```bash
curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-practice/main/bootstrap.sh \
  | GH_USER=<your-fork> EXAM=none bash
```

---

## Layout

```
bootstrap.sh        one-line install. Derives its file list from an exam count.
activate.sh         defines the shell commands. Generates the numbered ones.
cka.sh              the dispatcher. THE EXAMS TABLE LIVES HERE.
exams/examN.sh      tasks, walkthroughs and the grader for exam N
exams/setupN.sh     the seed: builds exam N's state in the cluster
scripts/            release tooling and the CI checks
docs/               everything the README links to
```

`cka.sh`'s `EXAMS` table is the single source of truth for which exams exist.
`activate.sh`, `bootstrap.sh` and CI all read it rather than repeating it, so
adding an exam should mean editing one line there.

---

## Anatomy of an exam

Every `examN.sh` is the same shape, and copying the nearest one is the right
way to start:

```bash
TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

Q[1]="what the candidate must do"
PTS[1]=7
SOL[1]="the commands, and nothing else"
WALK[1]="the walkthrough: what to inspect, what each flag does, the trap"

check(){ case "$1" in 1) ... ;; esac; }   # the grader
```

Conventions that are load-bearing:

- **13 tasks, 100 points.** Points are weighted by difficulty, not spread
  evenly. `grade` divides by the total, so they must add to 100.
- **`SOL` is commands only.** `explain` prints `WALK` and then `SOL`; a
  solution with prose in it reads as a duplicate walkthrough.
- **`WALK` ends with the trap.** Every walkthrough closes on the specific
  mistake that costs the points and the command that would have caught it.
  This is the part people come back for.
- **Escape every `"` inside `Q`/`SOL`/`WALK` as `\"`.** These are bash strings.
  An unescaped quote closes the string early, and the rest of the paragraph is
  then parsed as shell — which frequently *succeeds*, because English parses.
  `scripts/check-tasks.sh` exists entirely because that shipped once.
- **No partial credit.** A task passes or it does not, which is how the real
  exam's automated checks behave.

---

## Graders must fail closed

**A grader that awards points against a cluster that is not there is the worst
bug this repo can have.** It has happened six times. Every one had the same
shape — a deciding expression that is trivially true when `kubectl` prints
nothing:

```bash
[ "$(kubectl get x -o jsonpath='{.spec.foo}')" != "bar" ]   # "" != "bar" -> true
[ "$(kubectl ...)" = "$(kubectl ...)" ]                     # "" = ""     -> true
! kubectl get pod broken                                    # absent = correct,
                                                            # and all is absent
```

One exam scored 22/100 against a cluster that did not exist. So:

1. **Open every case arm with a positive gate.** `nsok ||  return 1`, or a
   `pyspec`, or something that proves you read a real object before you start
   reasoning about what is missing from it.
2. **Compare on a value you read, not on the absence of one.** Prefer
   `[ "$got" = "expected" ]` over `[ "$got" != "wrong" ]`.
3. **Run the audit.** `./scripts/audit-graders.sh` executes every grader with
   an empty `PATH` and requires all of them to score exactly `0/100`, then
   statically flags arms that decide on a negation without a gate in front.

---

## Adding an exam

1. Copy the closest `exams/examN.sh` and `exams/setupN.sh` to `N+1`.
2. Add one row to `EXAMS` in `cka.sh`:
   `number|name|examN.sh|setupN.sh|marker namespaces|topic|domain`.
   The **marker namespaces** are how "is this seeded?" is answered — the
   namespaces only this seed creates.
3. Bump `CKA_EXAM_COUNT`'s default in `bootstrap.sh`.
4. If the seed breaks the cluster, add its number to `DESTRUCTIVE` in `cka.sh`
   and give it a `restore` verb.
5. Add a section to `docs/exams.md`. CI fails if an exam is undocumented.
6. Add an `### Added` line to `CHANGELOG.md`.

The `cli`, `install` and `docs` CI jobs will tell you which of those you
forgot.

---

## Style

The comments in this repo explain **why**, and usually name the failure that
motivated the code. That is deliberate and worth keeping:

```bash
# One file per invocation: 'bash -n a b c' parses only the first and treats
# the rest as positional arguments, which silently checks nothing.
```

is worth ten of `# check syntax`. If you fix a bug, say what it was.

Other conventions:

- **bash 3.2.** No associative arrays, no `mapfile`, no `${var^^}`. macOS
  still ships 3.2 and people do run this on a Mac.
- **No emoji**, in code or in docs. `✔`/`✘` in output are the exception.
- **Prose in tasks and docs is British English**, and full sentences.

---

## Commits and pull requests

- One logical change per commit; the subject line says what changed and, when
  it is not obvious, why. `Fix a stale selection handing you the wrong exam` is
  a good one.
- New scripts need their executable bit **in the index**, not just on disk —
  CI checks this because a `cka.sh` committed `100644` gave every fresh clone
  a `permission denied`:
  ```bash
  chmod +x path/to/file.sh && git update-index --chmod=+x path/to/file.sh
  ```
- Do not bump `VERSION` or edit the README badge in a PR. Releases are cut
  with `./scripts/release.sh`; see [docs/development.md](docs/development.md).
- Say which Kubernetes and Helm versions you tested against. "Killercoda,
  v1.35.1, Helm 4.1.1" is the useful form.

---

## Reporting a problem

The most useful bug report here is a task that scores wrongly. Include:

- the exam and task number, and `cka version`
- `kubectl version` and, for the Helm exams, `helm version`
- what `explain N` told you to verify, and what that command actually printed

If a grader awarded points it should not have, say so first — that is a
security-shaped bug in a tool people use to decide whether they are ready to
sit an exam.
