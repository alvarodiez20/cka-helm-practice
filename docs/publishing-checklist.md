# Before you publish this

What is missing before posting on LinkedIn and having software engineers read
the code, in the order the gaps actually cost you something.

This is an audit of the repo as of 2.0.0, not a general checklist. Items marked
**done in 2.0.0** were fixed in this release and are listed so you know they
are covered.

---

## Blocking — do these before the post goes out

### 1. Run the remaining exams on a real cluster, end to end

**Exam 11 is done.** Verified on a Killercoda CKA playground — Kubernetes
v1.35.1, kustomize v5.7.1 vendored into kubectl — seeded from scratch,
scoring 0/100 before and **100/100** after applying its own reference
solution, and still 100/100 after a deliberately wrong attempt was applied
and repaired. That run found three real bugs, all now fixed:

- **Task 12's three faults surfaced in the reverse of the documented order.**
  The `namePrefix` shape error hides both of the others, because the file has
  to unmarshal before the kind can be checked or a path resolved. The
  walkthrough claimed kind → path → shape; the truth is shape → kind → path.
  Only a live run finds this.
- **Task 13's walkthrough said the overlay renders six objects.** It renders
  five. The grader counts for itself, so this misled the candidate rather
  than mis-scoring them, which is arguably worse.
- **Task 3's walkthrough understated what `commonLabels` does.** The apply is
  not atomic: the Service goes through, the Deployment is rejected on its
  immutable selector, and you are left half-applied. Plus kustomize now emits
  a deprecation warning that the walkthrough did not mention.

**Exam 1 is done too**, and it was worse than exam 11: three bugs made two
tasks unsolvable and one grader unsatisfiable, all shipping since 1.0.0. Task
11 waited five minutes on an image that could not exist, because task 9 set an
appVersion that `helm create` turns into the image tag. Task 2's own solution
rolled the release back and then forward into the break again. Task 8's
solution errored outright and its grader wanted a revision number nothing
could reach. A first run scored **76/100 from its own solutions**; after the
fixes it is 0/100 seeded and **100/100 solved**, in 25 seconds rather than
five minutes.

That run also caught two systemic problems: `setup1.sh` and `setup8.sh` never
reset the candidate's answer directory, so a re-seed carried 28 points over
from the previous attempt; and six solutions across four exams were menus
rather than scripts. Both are fixed, and `check-tasks.sh` now guards the
second.

**The other nine still need a pass under 2.0.0.** Their task content is
unchanged from 1.11.1, so the risk is the refactor rather than the exams —
but "the risk is low" is not the same as "it was run":

```bash
curl -sL .../bootstrap.sh | EXAM=none bash
cd ~/cka-practice && ./scripts/solve-and-grade.sh 2 4 7 9
./scripts/solve-and-grade.sh --list     # what can run unattended, and why not
```

The three destructive exams (`nodes`, `tshoot`, `gateway`) need a run each on
a cluster you are willing to lose, plus a `restore` afterwards to confirm the
restore works. Exam 3 needs internet; exam 8 needs a real control plane.

### 2. Finish the GitHub settings

**Done:** the repository is renamed to `cka-practice`, and the description
and topics are set (`kubernetes`, `cka`, `certification`, `helm`,
`kustomize`, `kubectl`, `networkpolicy`, `bash`, `cncf`, `devops`, `sre`,
`exam-preparation`). GitHub keeps a permanent redirect from the old name, so
existing clones and the old `curl | bash` URL still work — but use the new
URL everywhere in the post.

**Still to do, both in Settings → General:**

- **Features**: turn Issues **on**, Wiki and Projects off. Issues being off
  on a repo whose CONTRIBUTING.md tells people how to report a bad grader is
  a bad look.
- **Social preview image.** A LinkedIn link with no preview image gets
  materially less engagement, and this is a two-minute fix — a screenshot of
  `cka` with a couple of exams graded green would do.

### 3. Record the demo — **done**

`demo/cka-practice-kustomize.gif` is in the README and ready to attach to the
post: 924×624, 51s, 1.2 MB, comfortably inside LinkedIn's autoplay limit. Its
terminal output is a real run of exam 11 — real `kubectl`, real kustomize, the
real grader, 0/100 seeded and 100/100 solved.

It ends on thirteen green ✔ and `SCORE: 100/100 PASS`, which is the frame the
post is really for.

Two follow-ups if you want them:

- **A `DEMO=tour` recording as well.** The committed one is exam-specific; the
  tour shows the five verbs and survives the exam set changing under it. Useful
  as a second asset — a reply, a carousel slide.
- **Re-record when the verbs change.** That is the failure this whole file
  exists to prevent: the 1.x GIF still typed `exam3` and `q3 2` months after
  those stopped being the documented commands.

### 4. Push a tag and confirm the release publishes

`2.0.0` is committed but not released. The release workflow is stricter now —
it re-runs shellcheck, the grader audit and the task render at the tagged
commit, checks the tag is on `main`, and does a full install of the tagged
tree — so confirm it goes green before pointing anyone at it:

```bash
git push && git push origin v2.0.0
gh run watch          # or watch the Actions tab
gh release view v2.0.0
```

---

## Worth doing before engineers read the code

### 5. Tests that a correct answer scores — **done in 2.0.0**

This was the largest hole in the project: the grader audit proved the
*negative* case (nothing scores against no cluster) and nothing proved the
*positive* one, so a grader could have been unsatisfiable and every check
would still have been green.

`scripts/solve-and-grade.sh` closes it. It seeds an exam, asserts it scores
0/100 before anything is solved — which also catches a task the seed already
satisfies — applies either `tests/solutions/N.sh` or each task's own `solve`
output, and requires 100/100. `.github/workflows/e2e.yml` runs it weekly on a
`kind` cluster for the six exams that work single-node and unattended.

Verified working on Killercoda against exam 11. What is left is writing
`tests/solutions/N.sh` for any other exam whose `solve` output is prose
rather than commands, and watching the first scheduled run.

"I wrote a grader" and "I wrote a grader with a regression suite that proves
it is satisfiable" are different claims. The second one is now true.

### 6. Nothing states what happens on Helm 3 vs Helm 4, per exam, verifiably

`docs/internals.md` documents the differences and the graders detect the
version, but no CI job renders under both. A matrix job installing Helm 3.16
and Helm 4.x and running `helm template` against the exam's own fixtures would
back the claim up.

### 7. One file reviewers look for and will not find

- **`CODE_OF_CONDUCT.md`** — the Contributor Covenant, unmodified. Thirty
  seconds, and its absence is noticed on any repo that invites contributions.
  GitHub will add it for you: **Insights → Community Standards → Add**.

`CONTRIBUTING.md` and `SECURITY.md` now exist — the latter matters more than
its length suggests, because this project tells people to pipe a URL into
`bash` as root and then deliberately breaks their kubelet, and saying so
plainly is the difference between "unusual" and "suspicious". A GitHub issue
template
(`.github/ISSUE_TEMPLATE/`) with a "task scores wrongly" form would pay for
itself the first time somebody reports one without saying which exam.

### 8. The install story deserves an alternative to `curl | bash`

Piping a URL to a shell is normal for this kind of tool and it is also the
thing a security-minded reader will comment on. Pre-empt it in the README:
show the `git clone` route beside the one-liner, and mention that every
release is a signed-ish artefact — i.e. that the tag, the CHANGELOG entry and
the GitHub Release body are the same text, which the release workflow
enforces. Considering `git tag -s` for future releases would be a genuine
improvement rather than a gesture.

### 9. Pin the GitHub Actions

`actions/checkout@v4` is a moving tag. Pinning to a commit SHA is the current
supply-chain recommendation and Dependabot will keep them current for you if
you add `.github/dependabot.yml`. Small, visible, and reviewers notice.

---

## Nice to have

- **Coverage against the published curriculum, per objective.** The domain
  weights are covered; the individual competencies are not enumerated
  anywhere. A table mapping each curriculum bullet to the tasks that exercise
  it would be a genuinely useful artefact in its own right, and it would find
  the gaps.
- **A `--version`-aware `cka upgrade`.** Re-running `bootstrap.sh` is the
  upgrade path today and the README has to explain that repeatedly.
- **Shellcheck at `info` level.** Thirteen `SC2015` (`a && b || c` is not
  if-then-else) remain. Most are harmless; one or two are probably real.
- **A `kind` quick-start in the README** for people who will not use
  Killercoda. Six of the eleven exams work on single-node kind today.
- **Timing.** The real exam is two hours for ~15–20 tasks. Nothing here tracks
  time, and a `cka exam --timed` that starts a clock and prints a score at the
  end would make the practice materially closer to the thing being practised.

---

## What is already in good shape

Worth knowing, so the post can say it:

- **done in 2.0.0** — CI runs eight jobs, none needing a cluster, and
  shellcheck now blocks rather than advising.
- **done in 2.0.0** — the release workflow re-verifies at the tagged commit,
  refuses tags that are not on `main`, and installs the tagged tree before
  publishing.
- **done in 2.0.0** — `bootstrap.sh` derives its file list, so an exam can no
  longer exist in the repo and not install.
- **done in 2.0.0** — `scripts/solve-and-grade.sh` proves an exam is
  solvable, and a weekly `kind` job runs it. Exam 11 verified end to end on a
  real cluster.
- The grader audit is a real, unusual, defensible piece of engineering. It is
  the thing to lead the technical half of the post with, because "I wrote a
  static and behavioural audit to stop my own graders awarding free points" is
  a story about judgement rather than about volume.
- MIT licence, a real CHANGELOG, annotated tags, and release notes that are
  the CHANGELOG by construction.
