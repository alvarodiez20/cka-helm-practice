# LinkedIn post — draft

Two options. Both written in the repo's voice: concrete, no hype, no emoji.
Pick one, don't merge them.

Attach the GIF from `demo/out/` as the post image. It autoplays in-feed and
loops, which is why the GIF matters more than the wording here.

---

## Option A — lead with the trap (recommended)

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

## Option B — lead with the tool

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
which is worse than no image. Check the size before posting:
`du -h demo/out/*.gif`.

**Put the repo link in the post body, not the first comment.** The
link-in-comments trick is folklore; a plain link with a real preview does fine
and the post reads as less engineered.

**Hashtags:** three or four at the end, not inline. `#kubernetes #helm #cka
#devops` is enough. More reads as reach-farming.

**Timing:** Tuesday to Thursday morning, in your audience's timezone.

**Option A does better** because it teaches something in the first three lines,
before asking for anything. The repo becomes the answer to a question the
reader now has. Option B leads with "I built a thing", which needs the reader
to already care.

**If someone corrects the `--skip-crds` point in the comments,** they will
probably say it works for their chart — and they will be right, for a chart
with a real `crds/` directory. That is the whole distinction, so it is a good
comment to get and an easy one to answer well.
