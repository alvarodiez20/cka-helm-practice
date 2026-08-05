# LinkedIn post — draft

Three options. All written in the repo's voice: concrete, no hype, no emoji.
Pick one, don't merge them.

Attach `demo/cka-practice-kustomize.gif` as the post image. It autoplays
in-feed and loops, which is why the GIF matters more than the wording here.

---

## Option A — passed the exam, built the tool (recommended)

> I have recently passed the CKA.
>
> The February 2025 curriculum update added Helm, Kustomize and the Gateway
> API, and while I was revising I kept running into the same problem: plenty of
> practice material on the older topics, very little on the parts that had
> changed.
>
> So I built my own, and made it grade itself. Eleven mock exams that check the
> cluster's actual state rather than comparing you against an answer key, so
> there is no way through it by guessing.
>
> 66 to pass, same as the real exam. Every task explains the trap it is built
> around.
>
> One line on a Killercoda playground:
>
> `curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-practice/main/bootstrap.sh | bash`
>
> I hope someone finds it useful for passing the exam.
>
> github.com/alvarodiez20/cka-practice
>
> #kubernetes #cka #devops

About 115 words. It opens with a result, names the gap it was built to fill,
and stops. The GIF carries the rest — there is no point describing in prose
what the reader is already watching.

**The curriculum claim is checked.** The CKA changed on **18 February 2025**,
and the update added Helm, Kustomize, the Gateway API in place of Ingress, and
CRDs/Operators, while condensing the domains. That is the one line a commenter
will fact-check, and it holds:

- [Linux Foundation — CKA program changes](https://training.linuxfoundation.org/certified-kubernetes-administrator-cka-program-changes/)
- [Linux Foundation Forums — the 18 Feb 2025 changes](https://forum.linuxfoundation.org/discussion/868578/about-the-changes-release-on-the-18th-of-feb-2025-for-cka-certification)
- [devoriales — CKA exam updates for 2025](https://devoriales.com/post/377/certified-kubernetes-administrator-cka-exam-updates-for-2025)

If someone asks in the comments what was hard, the honest answer is the
graders, not the tasks: six of them were handing out points against a cluster
that did not exist, which is why there is now a test that runs every grader
with `kubectl` uninstalled and requires all eleven to score exactly 0. That is
a better second comment than it is a first paragraph.

---

## Option B — lead with the trap

> Install Argo CD with Helm, without installing its CRDs.
>
> Almost everyone reaches for `--skip-crds`. Try it and count:
>
> `helm template argocd argo/argo-cd --version 7.9.1 --skip-crds | grep -c 'kind: CustomResourceDefinition'`
>
> Three. The flag did nothing.
>
> `--skip-crds` only suppresses files in a chart's `crds/` directory. Argo CD
> keeps its CRDs in `templates/`, guarded by a value — so to Helm they are
> ordinary templates and no CRD flag touches them. The answer is
> `--set crds.install=false`.
>
> Now do Traefik, whose CRDs *are* in `crds/`. Plain `helm template` gives you
> zero of them, because `helm template` omits `crds/` by default. There you need
> `--include-crds`.
>
> Same-looking question. Opposite answers. Which one you get depends on how the
> chart author decided to package their CRDs, so the first move is always
> `helm show values` or unpacking the chart — not picking a flag.
>
> I built a practice suite for this: eleven mock CKA exams, 143 tasks, graded
> against a live cluster. The grader inspects release status, revision
> numbers, stored value types and rendered manifests — not your answer file. So
> guessing scores zero, which is the point.
>
> Runs in a Killercoda playground in about 30 seconds:
>
> `curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-practice/main/bootstrap.sh | bash`
>
> MIT. Every task has an `explain` walkthrough that covers what to inspect
> first, what each flag does, and the trap that usually costs the points.
>
> github.com/alvarodiez20/cka-practice

---

## Option C — lead with the tool

> I kept failing Helm questions in CKA practice for a reason I did not expect:
> I could recite the commands and still not verify my own work.
>
> So I wrote a grader instead of a question list.
>
> Eleven exams, 143 tasks, 100 points each, 66 to pass — the real CKA mark. Every
> task is something you do to a live cluster, and grading inspects the cluster
> afterwards: release status, revision numbers, whether a value was stored as a
> string or coerced to a number, whether the rendered manifest contains what it
> should. There is no answer key to match against, so `--set image.tag=1.25`
> and `--set-string image.tag=1.25` score differently — as they should.
>
> It covers all five domains at their real weights — troubleshooting is 30% of
> the exam and gets two exams to itself, three of which break a worker node,
> the scheduler or the CNI on purpose so there is something genuine to
> diagnose. Storage is 10% and gets one.
>
> One line in a Killercoda playground:
>
> `curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-practice/main/bootstrap.sh | bash`
>
> Then `cka use netpol`, `next`, `grade`, and `explain 4` when a task beats you.
>
> MIT, and the tasks are plain bash arrays — fork it and add your own.
>
> github.com/alvarodiez20/cka-practice

---

## Practical notes

**Attach the GIF, not a link to it.** LinkedIn autoplays and loops GIFs under
about 8 MB in-feed. Above that it silently converts the post to a still frame,
which is worse than no image. `demo/cka-practice-kustomize.gif` is 1.2 MB, so
it is fine — but check after any re-record: `du -h demo/*.gif`.

**Put the repo link in the post body, not the first comment.** The
link-in-comments trick is folklore; a plain link with a real preview does fine
and the post reads as less engineered.

**Hashtags:** three or four at the end, not inline. `#kubernetes #helm #cka
#devops` is enough. More reads as reach-farming.

**Timing:** Tuesday to Thursday morning, in your audience's timezone.

**Ordering.** A works because it opens with a result and then teaches. B works
if you would rather not lead with the certification — it teaches in the first
three lines and the repo becomes the answer to a question the reader now has.
C leads with "I built a thing", which needs the reader to already care.

**If someone corrects the `--skip-crds` point in the comments,** they will
probably say it works for their chart — and they will be right, for a chart
with a real `crds/` directory. That is the whole distinction, so it is a good
comment to get and an easy one to answer well.
