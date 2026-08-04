# Troubleshooting

[← back to the README](../README.md) · [the exams](exams.md) ·
[using it](usage.md)

---


**`cka: command not found`** — the shell functions are not loaded. Run
`source ~/cka-practice/activate.sh`. New shells pick it up automatically.

**`./exams/exam1.sh: No such file or directory`** — you are not in the repo directory.
Either `cd ~/cka-practice`, or load the functions and forget about
directories.

**Every task suddenly shows ✘** — the Killercoda session expired and took the
cluster with it. Re-seed the selected exam with `reset`, or any of them with `cka <name> reset`.

**I selected an exam and none of its namespaces exist** — on 1.9.0 and later
this does not happen: `cka use <name>` seeds the exam if it is missing. Before
that, `bootstrap.sh` seeded only exam 1 and `cka use` never checked, so
selecting any other exam gave you a task list with nothing behind it and you had
to run `reset` by hand every session. Re-run `bootstrap.sh` to pick up the fix.

**A task refers to a pod or namespace that does not exist** — the seed did not
finish. Check what is actually there:

```bash
kubectl get ns
kubectl get pods -A
```

If a namespace the exam needs is missing or `Terminating`, wait for it to
disappear and run `reset` again. This is most likely if you re-seeded on top of
a previous run and interrupted it, or ran two seeds at the same time. See
[Seeding and re-seeding an exam](#seeding-and-re-seeding-an-exam).

> Versions before 1.8.2 could hit this on their own: the seed deleted the old
> namespaces without waiting long enough, then recreated them with all kubectl
> output discarded, so a failed create was invisible and the script still
> printed `✔`. Every seed now waits properly and exits non-zero instead. If you
> installed before then, re-run `bootstrap.sh` to pick up the fix.

**The seed stops with `namespace ... is stuck in Terminating`** — something in
that namespace has a finalizer that is not completing. The seed already tries to
clear it. If it still will not go, find what is holding it:

```bash
kubectl get ns <name> -o jsonpath='{.spec.finalizers}{"\n"}'
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n1 kubectl get -n <name> --ignore-not-found 2>/dev/null
```

On a lab cluster the blunt fix is to drop the finalizers and re-seed:

```bash
kubectl get ns <name> -o json \
  | tr -d '\n' | sed 's/"finalizers": *\[[^]]*\]/"finalizers": []/' \
  | kubectl replace --raw "/api/v1/namespaces/<name>/finalize" -f -
```

**Exam 4: my policies are all correct but nothing is ever blocked** — your CNI
does not enforce NetworkPolicy. `netcheck` says so explicitly. Grading is
unaffected; seeing traffic actually denied needs Calico or Cilium.

**Exam 5: `setup5.sh` says it cannot ssh to the node** — it has to stop the
kubelet and edit files there, which needs passwordless ssh and root. On
Killercoda `ssh node01` works out of the box. If your worker has another name,
set `CKA_NODE=<name>`.

**Exam 5: I have wrecked the node and want out** — `exam5restore` copies the
pristine `config.yaml` and `kubelet.conf` back from the node's backup directory,
re-enables and restarts the kubelet, clears the taint and cordon, and waits for
`Ready`.

**Exam 6: I fixed a Deployment and the pod still will not start** — task 1.
While `kube-scheduler` is down nothing new can be placed, so a correct fix still
leaves you with a `Pending` pod. Also mind the CrashLoopBackOff backoff: it grows
to 5 minutes, so a fixed pod can take minutes to retry. `kubectl delete pod` skips
the wait.

**Exam 4: a task scores zero and the YAML looks right** — for the policy tasks,
`kubectl get netpol <name> -o yaml` and compare the *structure*, not the text.
Count the dashes under `from:`; one element means AND, two mean OR. `explain N`
ends with the exact distinction the grader makes.

**Exam 10: tasks 6 to 9 score zero and `kubectl get gateway` says the resource
does not exist** — the Gateway API is not part of Kubernetes. It ships as CRDs
on its own release schedule, and `setup10.sh` installs them for you if it can
reach GitHub. If it could not, install them by hand and re-grade:

```bash
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
```

**Exam 10: my Ingress never gets an ADDRESS and my Gateway is never Programmed**
— nothing is installed to give them one, on purpose. Both are graded on the
object you wrote, as they are on the real exam.

**Exam 10: I want the broken node back** — `exam10restore` removes the planted
config, un-disables the real ones, restarts the container runtime and waits for
`Ready`. If the node is still NotReady afterwards, check that nothing is left:
`ssh node01 ls -l /etc/cni/net.d`.

**Task 1 of exam 2 fails after a session restart** — the local chart repo server
died. `exam2reset` restarts it.

**`setup3.sh` says it cannot reach the chart repositories** — exam 3 installs
from the real internet by design. If the environment is offline, use exam 1 or
exam 2, which serve their charts from `localhost`.

**Exam 3 task 11 always scores zero** — `--set-json` needs Helm 3.10+. Check
`helm version`.

**A task scores zero and you are sure it is right** — run `grade N` on its own,
then work through `explain N`; each walkthrough ends with the exact verification
commands the grader uses.
