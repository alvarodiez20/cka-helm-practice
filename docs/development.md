# Development

Versioning, cutting a release, and what CI checks.

[← back to the README](../README.md)

---

## Versioning

The exam suite is versioned with [semantic versioning](https://semver.org): MAJOR
if existing answers or scripts may behave differently, MINOR for new tasks or
commands, PATCH for fixes. See [CHANGELOG.md](../CHANGELOG.md), or ask:

```bash
cka version
```

Every released version is an annotated git tag, and every tag has a
[GitHub Release](https://github.com/alvarodiez20/cka-practice/releases)
whose notes are that version's CHANGELOG entry.

### Cutting a release

A version lives in four places — `VERSION`, the README badge, the `## [X.Y.Z]`
CHANGELOG heading, and the git tag — so one command changes all four:

```bash
# 1. write the CHANGELOG entry first. The script will not invent one:
#    that text becomes the tag message and the GitHub Release body.
$EDITOR CHANGELOG.md

# 2. then
./scripts/release.sh minor              # or major / patch / 2.3.4
./scripts/release.sh minor --dry-run    # show the diff, write nothing

# 3. push the tag; the release workflow publishes from it
git push && git push origin v1.11.0
```

`./scripts/release.sh --check` verifies the four agree and is what CI runs on
every push. It refuses to release from a dirty tree, over an existing tag, or
without a CHANGELOG entry.

## What CI checks

Seven jobs, none of which needs a cluster. Everything here runs locally too,
and running it locally before pushing is faster than waiting for the run.

| Job | What it catches | Run it yourself |
|---|---|---|
| `shell` | a syntax error, or a script committed without its executable bit | `git ls-files '*.sh' \| xargs -n1 bash -n` |
| `shellcheck` | everything shellcheck flags at warning and above | `git ls-files '*.sh' \| xargs shellcheck -S warning -e SC2086,SC2181,SC1090,SC1091,SC2034,SC2207,SC2046` |
| `graders` | a grader that awards points with no cluster — see below | `./scripts/audit-graders.sh` |
| `tasks` | a task string that breaks apart mid-render | `./scripts/check-tasks.sh` |
| `cli` | an exam or a shell function bound to a script that moved | see `ci.yml` |
| `install` | `bootstrap.sh`, `cka.sh` and the repo disagreeing about which exams exist — plus a real install over HTTP | see `ci.yml` |
| `version` | `VERSION`, the badge, the CHANGELOG and the tags disagreeing | `./scripts/release.sh --check` |
| `docs` | an exam nobody documented, or a relative link that resolves to nothing | see `ci.yml` |

**`shellcheck` blocks as of 2.0.0.** It ran with `continue-on-error` for
eleven releases on the grounds that the backlog had never been triaged —
which meant nobody ever read the output and it caught nothing. Triaged, the
backlog turned out to be three codes, all deliberate. They are now excluded
by name with a reason each, in `ci.yml`, and everything else fails the build.
Do not add to that list without a comment saying why.

**`scripts/audit-graders.sh` is the one worth knowing about.** Graders here
must **fail closed**, and six have not. Each had the same shape: a check whose
deciding expression is trivially true when `kubectl` returns nothing —
`[ "$(kubectl ...)" != "true" ]` is true when the command printed nothing at
all. One exam awarded 22 points against a cluster that did not exist.

The audit runs every grader with an empty `PATH` and requires every one of
them to score exactly `0/100`, then statically flags any task that decides on
a negation without first proving the cluster is there.

```bash
./scripts/audit-graders.sh
```

### What the release workflow adds

Pushing a `v*` tag fires `release.yml`, which re-runs shellcheck, the grader
audit and the task render **at the tagged commit** — CI ran on the branch, and
a bad merge or a tag on the wrong SHA diverges there and nowhere else. It then
checks that the tag is an ancestor of `main` (`curl | bash` installs from
`main`, so a tag off a branch would publish something nobody can install), does
a full install of the tagged tree over local HTTP, and only then creates the
GitHub Release from the CHANGELOG section.
