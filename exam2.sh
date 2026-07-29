#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam2.sh
#  Second set of 13 CKA-style Helm tasks. 100 points. Pass: 66.
#  Covers ground exam 1 does not: repo management, values files
#  and precedence, --atomic, subcharts, chart debugging.
#
#    ./exam2.sh            list the tasks
#    ./exam2.sh q 4        show task 4
#    ./exam2.sh grade      grade everything, print the score
#    ./exam2.sh explain 4  step-by-step walkthrough of task 4
#    ./exam2.sh help       full usage
#    ./exam2.sh version    print the exam suite version
#    ./exam2.sh reset      re-seed the cluster (runs setup2.sh)
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers2"
EX2="$BASE/exam2"
REPO_NAME="extrarepo"
REPO_URL="http://127.0.0.1:${CKA_HELM2_PORT:-8880}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

# The command names differ depending on whether activate.sh is loaded.
if [ -n "${EXAM_HOME:-}" ]; then
  CL="exam2"; CQ="q2"; CG="grade2"; CE="explain2"; CS="solve2"; CH="exam2help"
else
  CL="./exam2.sh"; CQ="./exam2.sh q"; CG="./exam2.sh grade"
  CE="./exam2.sh explain"; CS="./exam2.sh solve"; CH="./exam2.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

Q[1]="A second chart repository is being served at ${REPO_URL}, but Helm
does not know about it yet.
Register it under the name '${REPO_NAME}', refresh the local cache so its
charts become searchable, and write the resulting repository list into
${ANS}/q1.txt"
PTS[1]=6
SOL[1]="helm repo add ${REPO_NAME} ${REPO_URL}
helm repo update
helm repo list > ${ANS}/q1.txt"
WALK[1]="1. Confirm the repository really is up before blaming Helm. It is a plain
   HTTP server, and every chart repo must expose an index.yaml:

     curl -s ${REPO_URL}/index.yaml | head

2. Register it. 'helm repo add' takes a local alias and the URL; the alias is
   what you will type in front of chart names from now on:

     helm repo add ${REPO_NAME} ${REPO_URL}

3. Refresh the cache. This is the step people skip. 'add' fetches the index
   once; 'update' re-fetches every repo's index, and without a current cache
   'helm search repo' shows nothing or stale versions:

     helm repo update

4. Write the list to the answer file:

     helm repo list > ${ANS}/q1.txt

5. Verify the charts are actually searchable now, which is what the task
   really means by 'become searchable':

     helm search repo ${REPO_NAME} --versions

   You should see web-stack at 1.0.0, 1.1.0 and 2.0.0.

Why this matters: almost every other task in this exam installs from
'${REPO_NAME}/web-stack'. If this one is not done, most of the rest cannot
be, so do it first."

Q[2]="Write the DEFAULT values of the chart ${REPO_NAME}/web-stack at version
2.0.0 into ${ANS}/q2.yaml
Do not install the chart and do not render its manifests: the file must hold
the values, not Kubernetes objects."
PTS[2]=6
SOL[2]="helm show values ${REPO_NAME}/web-stack --version 2.0.0 > ${ANS}/q2.yaml"
WALK[2]="1. 'helm show values' prints a chart's values.yaml without installing or
   rendering anything. It is how you find out what you are allowed to
   override before you write a single --set:

     helm show values ${REPO_NAME}/web-stack --version 2.0.0

2. Redirect it to the answer file:

     helm show values ${REPO_NAME}/web-stack --version 2.0.0 > ${ANS}/q2.yaml

3. Verify. The file should contain keys like replicaCount, pullPolicy and
   ingress, and NO 'kind:' lines at all:

     cat ${ANS}/q2.yaml
     grep -c 'kind:' ${ANS}/q2.yaml     # expect 0

Know the whole family, it comes up constantly:

     helm show values    just values.yaml
     helm show chart     just Chart.yaml (version, appVersion, dependencies)
     helm show readme    the chart's README
     helm show crds      any CRDs the chart ships
     helm show all       all of the above at once

Common traps: reaching for 'helm template' here. That renders Deployments and
Services, so the file fills up with 'kind:' lines and fails the check."

Q[3]="Create a values file at ${ANS}/q3-values.yaml that sets 2 replicas,
a service of type NodePort, and the environment tier 'gold'.
Then install ${REPO_NAME}/web-stack version 1.1.0 as release 'api' in the
namespace 'api', which does not exist, USING THAT FILE rather than --set."
PTS[3]=8
SOL[3]="cat > ${ANS}/q3-values.yaml <<'EOF'
replicaCount: 2
service:
  type: NodePort
env:
  TIER: gold
EOF

helm install api ${REPO_NAME}/web-stack --version 1.1.0 \\
  -n api --create-namespace -f ${ANS}/q3-values.yaml"
WALK[3]="1. Look at the chart's own values first so you nest your keys the same way
   it expects. Guessing the structure is the usual reason this fails:

     helm show values ${REPO_NAME}/web-stack --version 1.1.0

   You will see replicaCount at the top level, and 'type' nested under
   'service', and 'TIER' nested under 'env'.

2. Write the file with exactly that shape:

     cat > ${ANS}/q3-values.yaml <<'EOF'
     replicaCount: 2
     service:
       type: NodePort
     env:
       TIER: gold
     EOF

   (Typing that by hand in vi is fine too. If you paste the heredoc, the body
   must start at column 0.)

   You only list what you want to change. Every key you omit keeps the
   chart's default, exactly like --set.

3. Install with -f (long form --values), pinning the version and creating the
   namespace:

     helm install api ${REPO_NAME}/web-stack --version 1.1.0 \\
       -n api --create-namespace -f ${ANS}/q3-values.yaml

4. Verify all three overrides landed:

     helm list -n api                    # CHART web-stack-1.1.0
     helm get values api -n api          # replicaCount, service.type, env.TIER
     kubectl get svc -n api              # TYPE NodePort

-f versus --set: they do the same job, but a file is reviewable, diffable and
can go in git, so it is what you use for anything real. --set is for one-off
overrides. You can combine both; --set wins over -f."

Q[4]="The files ${EX2}/base.yaml and ${EX2}/override.yaml already exist.
Upgrade the release 'api' passing BOTH of them, in the order that leaves the
release running 5 replicas while its environment tier ends up as 'base'."
PTS[4]=8
SOL[4]="helm upgrade api ${REPO_NAME}/web-stack -n api \\
  -f ${EX2}/base.yaml -f ${EX2}/override.yaml"
WALK[4]="1. Read both files before deciding the order. The whole task is precedence:

     cat ${EX2}/base.yaml        # replicaCount: 3, env.TIER: base
     cat ${EX2}/override.yaml    # replicaCount: 5

2. The rule: when the same key appears in several -f files, THE LAST ONE WINS.
   Keys that appear in only one file are simply merged in.

   So with base first and override second:

     replicaCount  3 from base, then overridden to 5   -> 5
     env.TIER      only in base, nothing overrides it  -> base

   which is exactly what the task asks for:

     helm upgrade api ${REPO_NAME}/web-stack -n api \\
       -f ${EX2}/base.yaml -f ${EX2}/override.yaml

   Reverse the two and replicaCount comes out as 3, because base would then
   have the last word. That is the trap.

3. Verify:

     helm get values api -n api      # replicaCount: 5, env.TIER: base
     kubectl get deploy -n api       # READY 5/5

Note what this upgrade also does: because you did not pass --reuse-values, the
value set is rebuilt from the chart defaults plus these two files, so the
NodePort service from task 3 reverts to the chart's ClusterIP. That is correct
behaviour for -f, and the grader does not mind here, but it is exactly the kind
of silent loss that --reuse-values exists to prevent.

Full precedence order, lowest to highest: chart values.yaml, then each -f in
the order given, then --set, then --set-string / --set-file."

Q[5]="The release 'shop' does not exist yet, in a namespace 'shop' that does not
exist either. Deploy ${REPO_NAME}/web-stack version 2.0.0 there using a SINGLE
command form that works whether or not the release already exists, and leave
the release at revision 2 or higher."
PTS[5]=7
SOL[5]="helm upgrade --install shop ${REPO_NAME}/web-stack --version 2.0.0 \\
  -n shop --create-namespace
# run the exact same command a second time -> revision 2"
WALK[5]="1. The command form the task is describing is 'helm upgrade --install'. It
   upgrades the release if it exists, and installs it if it does not. This is
   what every CI pipeline uses, because it needs to be safe to re-run:

     helm upgrade --install shop ${REPO_NAME}/web-stack --version 2.0.0 \\
       -n shop --create-namespace

   Note --create-namespace works with 'upgrade --install' too, not just with
   'install'.

2. Run the identical command again. That is what gets you to revision 2 and
   demonstrates the point of the flag: no error, no 'release already exists',
   just a new revision.

     helm upgrade --install shop ${REPO_NAME}/web-stack --version 2.0.0 \\
       -n shop --create-namespace

3. Verify:

     helm list -n shop                 # REVISION 2, CHART web-stack-2.0.0
     helm history shop -n shop         # two entries

Contrast the alternatives: a plain 'helm install' fails the second time with
'cannot re-use a name that is still in use', and a plain 'helm upgrade' fails
the first time with 'release: not found'. Only the combination is safe to run
blind, which is why it is worth having in your fingers."

Q[6]="Dump the manifests that Helm has actually STORED for the live release 'api'
into ${ANS}/q6.yaml
This must be what the release really consists of, not a fresh local render of
the chart."
PTS[6]=7
SOL[6]="helm get manifest api -n api > ${ANS}/q6.yaml"
WALK[6]="1. 'helm get manifest' returns the YAML Helm has recorded for the release, as
   it was applied. It reads the release record in the cluster, so it reflects
   the values that release is genuinely running with:

     helm get manifest api -n api > ${ANS}/q6.yaml

2. Verify it contains the real objects:

     grep 'kind:' ${ANS}/q6.yaml       # Deployment and Service

The distinction the task is testing:

     helm get manifest    what this release IS, read from the cluster
     helm template        what a chart WOULD produce, rendered locally

They can differ, and the gap is usually the interesting part when you are
debugging: someone upgraded with different values, or the chart in the repo
moved on since the release was installed.

The rest of the 'helm get' family is worth knowing for the exam:

     helm get values      the values (add -a for defaults too)
     helm get manifest    the rendered objects
     helm get notes       the NOTES.txt shown after install
     helm get hooks       the chart's hooks
     helm get all         everything at once

Common traps: using 'helm template' and getting a file that looks plausible.
It is not the stored manifest, and after task 4 its replica count would not
even match."

Q[7]="The release 'stage-app' in the namespace 'stage' has been through several
revisions, each with different values.
Recover the values it was running with at REVISION 2 exactly, and write them
into ${ANS}/q7.yaml"
PTS[7]=8
SOL[7]="helm history stage-app -n stage
helm get values stage-app -n stage --revision 2 > ${ANS}/q7.yaml"
WALK[7]="1. Look at the history first to see what revisions exist and what changed:

     helm history stage-app -n stage

2. 'helm get values' accepts --revision, which is the whole point of the task.
   Without it you get the CURRENT values (revision 3, tier 'three'); with it
   you get the values as they were at that point in time:

     helm get values stage-app -n stage --revision 2 > ${ANS}/q7.yaml

3. Verify you captured revision 2 and not the current one:

     cat ${ANS}/q7.yaml       # replicaCount: 2, env.TIER: two

   If you see 'three', you forgot --revision.

Why this is useful outside the exam: it tells you what a release looked like
before someone broke it, which is how you decide what to roll back TO rather
than just rolling back blindly. --revision works on 'helm get manifest' and
'helm get all' as well.

Note you can read this without touching the release at all: it is pure
inspection, no upgrade, no rollback."

Q[8]="Upgrade 'stage-app' in namespace 'stage' to the image tag '9.9.9-nope',
which does not exist.
The upgrade must NOT leave the release broken: if it fails, it has to undo
itself automatically and leave the release deployed and healthy, on its own,
without you running a rollback afterwards.
Give it a timeout of 30s so you are not waiting five minutes."
PTS[8]=9
SOL[8]="helm upgrade stage-app ${REPO_NAME}/web-stack -n stage \\
  --set image.tag=9.9.9-nope --atomic --timeout 30s
# it fails, rolls itself back, and the release stays deployed"
WALK[8]="1. The flag being tested is --atomic. It means: wait for the release to
   become ready, and if it does not, roll back to the previous revision
   automatically. --atomic implies --wait, so you do not need both.

     helm upgrade stage-app ${REPO_NAME}/web-stack -n stage \\
       --set image.tag=9.9.9-nope --atomic --timeout 30s

2. Expect the command to FAIL, loudly, after about 30 seconds. That is the
   task working, not you making a mistake. The message reads something like
   'release stage-app failed, and has been rolled back due to atomic being
   set'.

   Without --timeout it would sit there for the default 5 minutes before
   giving up.

3. Verify the release survived intact. This is the part that matters:

     helm list -n stage                  # STATUS deployed, not failed
     helm history stage-app -n stage     # a failed revision, then a rollback
     helm get values stage-app -n stage  # TIER still three, no 9.9.9-nope
     kubectl get pods -n stage           # Running

   The history is the interesting bit: you get one revision for the failed
   upgrade and another for the automatic rollback, so the revision number
   jumps by two.

Why you want this habit: without --atomic, the same failed upgrade leaves the
release in status 'failed' with dead pods, and you have to notice and run
'helm rollback' yourself. Compare:

     --wait     fail and STAY broken, telling you about it
     --atomic   fail, undo, and leave the last good state running

The cost is time: --atomic cannot return until it knows, so always pair it
with a --timeout you can live with."

Q[9]="The chart at ${EX2}/brokenchart does not pass 'helm lint'.
Fix it until it does. When you are done it must still be named 'brokenchart',
declare apiVersion v2, and have chart version 1.2.0.
There is more than one fault, and they do not all show up at once."
PTS[9]=10
SOL[9]="# 1st pass: Chart.yaml has no apiVersion and an invalid version
sed -i '1i apiVersion: v2' ${EX2}/brokenchart/Chart.yaml
sed -i 's/^version:.*/version: 1.2.0/' ${EX2}/brokenchart/Chart.yaml
helm lint ${EX2}/brokenchart

# 2nd pass: now the templates get rendered, and 'image:' is mis-indented
# in templates/deployment.yaml - line it up under '- name: app'
sed -i 's/^        image:/          image:/' ${EX2}/brokenchart/templates/deployment.yaml
helm lint ${EX2}/brokenchart"
WALK[9]="1. Run the linter and actually read it. Do not start editing from a guess:

     helm lint ${EX2}/brokenchart

   Two errors about Chart.yaml:

     apiVersion is required. The value must be either \"v1\" or \"v2\"
     version 'not-a-version' is not a valid SemVer

   plus a knock-on complaint that 'chart type is not valid in apiVersion'
   (because with no apiVersion, the 'type' field has no business being
   there), and a final 'unable to load chart'.

2. Fix Chart.yaml. Add the apiVersion line and put a real semver in version.
   The task dictates both values, and 1.2.0 must be a valid semver:

     apiVersion: v2
     name: brokenchart
     description: ...
     type: application
     version: 1.2.0
     appVersion: \"1.0.0\"

   In place, if you prefer not to use vi:

     sed -i '1i apiVersion: v2' ${EX2}/brokenchart/Chart.yaml
     sed -i 's/^version:.*/version: 1.2.0/' ${EX2}/brokenchart/Chart.yaml

3. Lint AGAIN. This is the lesson of the task: the first round of errors was
   hiding the next one. Helm could not load the chart at all while the
   version was invalid, so it never got as far as rendering templates. Now
   it does, and a new error appears:

     templates/deployment.yaml: unable to parse YAML: ... yaml: line 16:
     did not find expected '-' indicator

4. Go to that line. In templates/deployment.yaml the container list reads:

           containers:
             - name: app
             image: \"...\"          <- wrong: same indent as '- name'

   'image' has to be a key of the same list item as 'name', so it needs to
   line up with 'name', two spaces further in:

           containers:
             - name: app
               image: \"...\"

5. Lint a third time. Expect '1 chart(s) linted, 0 chart(s) failed'. The
   remaining '[INFO] icon is recommended' line is informational and does not
   count as a failure.

6. Confirm it renders, which is stronger than lint passing:

     helm template t ${EX2}/brokenchart

Method to take into the real exam: lint, fix the top error, lint again,
repeat. Errors cascade and mask each other, so fixing everything you think
you see in one pass and walking away is how you end up still broken."

Q[10]="Render ONLY the Service template of ${REPO_NAME}/web-stack version 2.0.0
into ${ANS}/q10.yaml
The file must contain the Service and nothing else, and nothing may be
installed into the cluster."
PTS[10]=7
SOL[10]="helm template svc ${REPO_NAME}/web-stack --version 2.0.0 \\
  --show-only templates/service.yaml > ${ANS}/q10.yaml"
WALK[10]="1. If you are unsure what the template files are called, look inside the
   chart first:

     helm show chart ${REPO_NAME}/web-stack --version 2.0.0
     helm template svc ${REPO_NAME}/web-stack --version 2.0.0 | grep 'kind:'

2. --show-only (short form -s) filters the render down to one template file.
   The path is relative to the chart root, so it includes 'templates/':

     helm template svc ${REPO_NAME}/web-stack --version 2.0.0 \\
       --show-only templates/service.yaml > ${ANS}/q10.yaml

3. Verify the filter really worked:

     grep 'kind:' ${ANS}/q10.yaml      # Service, and only Service

Details worth knowing:

  - the path must match a real file in the chart, or Helm errors with
    'could not find template ... in chart'. It is not a glob over object
    kinds, it is a filename filter.
  - you can pass --show-only more than once to keep several files.
  - for a subchart's template the path is 'charts/<subchart>/templates/x.yaml'.

Common traps: writing '--show-only service.yaml' without the 'templates/'
prefix, or rendering everything and hand-deleting the Deployment, which works
but is slow and error-prone under time pressure."

Q[11]="Somewhere in this cluster there is a Helm release in the 'failed' state.
Find it, wherever it is, and write its location into ${ANS}/q11.txt
in exactly this format, on one line:

    namespace/releasename"
PTS[11]=8
SOL[11]="helm list -A --failed
echo broken-77/checkout > ${ANS}/q11.txt"
WALK[11]="1. Search the whole cluster and filter by state. 'helm list' hides anything
   that is not 'deployed' unless you ask, and it only looks at one namespace
   unless you pass -A:

     helm list -A --failed

   That gives you release 'checkout' in namespace 'broken-77'.

2. Write the answer in the exact format asked for, namespace first:

     echo broken-77/checkout > ${ANS}/q11.txt

3. Verify, and have a look at why it failed while you are here:

     cat ${ANS}/q11.txt
     helm status checkout -n broken-77
     kubectl get pods -n broken-77          # ImagePullBackOff

The status filters are all worth knowing, because a release you cannot see is
the most common 'Helm is broken' report you will ever get:

     helm list -A                 deployed only
     helm list -A --failed        failed
     helm list -A --pending       stuck mid-install or mid-upgrade
     helm list -A --uninstalled   uninstalled but kept with --keep-history
     helm list -A --all           every state at once, the safest habit

Read task 13 before you go any further: it removes this release for good. Do
this task first, or you will have nothing left to find."

Q[12]="The chart at ${EX2}/parentchart declares 'web-stack' as a subchart.
Install it as release 'portal' in the namespace 'shop' so that the SUBCHART
runs 4 replicas, setting that from the parent rather than editing the
subchart."
PTS[12]=9
SOL[12]="helm install portal ${EX2}/parentchart -n shop \\
  --set web-stack.replicaCount=4"
WALK[12]="1. Understand how a parent passes values down. In the parent's values, a
   subchart's settings live in a block NAMED AFTER THE SUBCHART. Look:

     cat ${EX2}/parentchart/Chart.yaml     # dependencies: web-stack 1.0.0
     cat ${EX2}/parentchart/values.yaml    # a 'web-stack:' block
     ls ${EX2}/parentchart/charts/         # web-stack-1.0.0.tgz, vendored

   So the subchart's own 'replicaCount' is addressed from the parent as
   'web-stack.replicaCount'.

2. Install, overriding through that path:

     helm install portal ${EX2}/parentchart -n shop \\
       --set web-stack.replicaCount=4

   The namespace 'shop' already exists if you did task 5; if not, add
   --create-namespace.

3. Verify the value reached the subchart's Deployment, not just the release
   record. This is the check that matters, because a typo in the subchart name
   is silently accepted by --set and simply does nothing:

     helm get values portal -n shop           # web-stack.replicaCount: 4
     kubectl get deploy -n shop               # portal-web-stack, 4 replicas

   You should also see the parent's own ConfigMap, 'portal-parent'.

Equivalent with a values file, which is what you would do for real:

     cat > /tmp/portal.yaml <<'EOF'
     web-stack:
       replicaCount: 4
     EOF
     helm install portal ${EX2}/parentchart -n shop -f /tmp/portal.yaml

Common traps: setting '--set replicaCount=4' at the top level. That sets a
value on the PARENT chart, which nothing reads, so the command succeeds and
the subchart stays at 1 replica. Getting no error is not the same as it
having worked, which is why step 3 checks the Deployment itself."

Q[13]="Remove the failed release you located in task 11 from the cluster
COMPLETELY, history included: afterwards 'helm history' must not be able to
find it at all."
PTS[13]=7
SOL[13]="helm uninstall checkout -n broken-77
# no --keep-history: the release record goes too"
WALK[13]="1. Make sure task 11 is done and its answer file is written. Once this
   release is gone there is no way to look it up again.

2. Uninstall it plainly. A bare 'helm uninstall' purges the release record
   along with the objects; that is the default, and --keep-history is what
   you would add to avoid it:

     helm uninstall checkout -n broken-77

3. Verify it is gone in every sense:

     helm list -n broken-77 --all         # empty
     helm list -A --failed                # checkout no longer listed
     helm history checkout -n broken-77   # Error: release: not found

   That last error is the pass condition. While the history exists, the
   release is still recoverable with 'helm rollback'; once it does not, it
   is not.

Where the history actually lives: Helm keeps one Secret per revision in the
release's namespace. You can watch them disappear:

     kubectl get secret -n broken-77 | grep sh.helm.release

Contrast with exam 1, tasks 7 and 8, which are the mirror image of this one:
there you kept the history with --keep-history precisely so the release could
be brought back. Same subcommand, opposite intent, and the difference is one
flag you cannot undo."

# ─────────── grading helpers ───────────
hfield(){ # release ns field -> value
  helm list -n "$2" --all --filter "^$1\$" -o json 2>/dev/null \
    | tr '{},' '\n' | grep "\"$3\":" | head -1 | cut -d'"' -f4
}
hnum(){ local v; v="$(hfield "$1" "$2" "$3")"; echo "${v:-0}"; }
huninstalled(){ helm list -n "$2" --uninstalled -o json 2>/dev/null | grep -q "\"$1\""; }
hvals(){ helm get values "$1" -n "$2" ${3:-} -o json 2>/dev/null; }
nsexists(){ kubectl get ns "$1" >/dev/null 2>&1; }
filehas(){ [ -f "$1" ] && grep -q "$2" "$1"; }
filelacks(){ [ -f "$1" ] && ! grep -q "$2" "$1"; }
replicas(){ kubectl get deploy "$2" -n "$1" -o jsonpath='{.spec.replicas}' 2>/dev/null; }

check(){
  case "$1" in
    1) helm repo list -o json 2>/dev/null | grep -q "\"$REPO_NAME\"" \
       && helm search repo "$REPO_NAME/web-stack" -o json 2>/dev/null | grep -q 'web-stack' \
       && filehas "$ANS/q1.txt" "$REPO_NAME" ;;
    2) filehas "$ANS/q2.yaml" "replicaCount" \
       && filehas "$ANS/q2.yaml" "pullPolicy" \
       && filehas "$ANS/q2.yaml" "ingress" \
       && filelacks "$ANS/q2.yaml" "^kind:" ;;
    3) nsexists api \
       && [ "$(hfield api api status)" = "deployed" ] \
       && [ "$(hfield api api chart)" = "web-stack-1.1.0" ] \
       && [ -f "$ANS/q3-values.yaml" ] \
       && filehas "$ANS/q3-values.yaml" "NodePort" \
       && filehas "$ANS/q3-values.yaml" "gold" ;;
    4) hvals api api | grep -q '"replicaCount":5' \
       && hvals api api | grep -q '"TIER":"base"' ;;
    5) nsexists shop \
       && [ "$(hfield shop shop status)" = "deployed" ] \
       && [ "$(hfield shop shop chart)" = "web-stack-2.0.0" ] \
       && [ "$(hnum shop shop revision)" -ge 2 ] ;;
    6) filehas "$ANS/q6.yaml" "kind: Deployment" \
       && filehas "$ANS/q6.yaml" "kind: Service" ;;
    7) filehas "$ANS/q7.yaml" "TIER: two" \
       && filehas "$ANS/q7.yaml" "replicaCount: 2" \
       && filelacks "$ANS/q7.yaml" "three" ;;
    8) [ "$(hfield stage-app stage status)" = "deployed" ] \
       && [ "$(hnum stage-app stage revision)" -ge 4 ] \
       && hvals stage-app stage | grep -q '"TIER":"three"' \
       && ! hvals stage-app stage | grep -q '9.9.9-nope' ;;
    9) [ -f "$EX2/brokenchart/Chart.yaml" ] \
       && grep -Eq '^apiVersion:[[:space:]]*v2[[:space:]]*$' "$EX2/brokenchart/Chart.yaml" \
       && grep -Eq '^name:[[:space:]]*brokenchart[[:space:]]*$' "$EX2/brokenchart/Chart.yaml" \
       && grep -Eq '^version:[[:space:]]*1\.2\.0[[:space:]]*$' "$EX2/brokenchart/Chart.yaml" \
       && helm lint "$EX2/brokenchart" >/dev/null 2>&1 ;;
    10) filehas "$ANS/q10.yaml" "kind: Service" \
       && filelacks "$ANS/q10.yaml" "kind: Deployment" ;;
    11) [ -f "$ANS/q11.txt" ] \
       && [ "$(tr -d '[:space:]' < "$ANS/q11.txt")" = "broken-77/checkout" ] ;;
    12) [ "$(hfield portal shop status)" = "deployed" ] \
       && hvals portal shop | grep -q 'web-stack' \
       && hvals portal shop | grep -q '"replicaCount":4' \
       && [ "$(replicas shop portal-web-stack)" = "4" ] ;;
    # nsexists first: without it, an unreachable cluster makes 'helm history'
    # fail too, and the task would score free points.
    13) nsexists broken-77 \
       && ! helm history checkout -n broken-77 >/dev/null 2>&1 \
       && ! huninstalled checkout broken-77 ;;
    *) return 2 ;;
  esac
}

valid_n(){
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]
}

need_n(){
  if ! valid_n "${1:-}"; then
    printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" \
      "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2
    exit 1
  fi
}

show(){
  printf "\n%s┌─ Exam 2 · Task %s/%s ─ %s points%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N"
  printf "%s└%s\n" "$B" "$N"
  echo "${Q[$1]}"
  printf "\n%s  when you are done:  %s %s      stuck?  %s %s%s\n\n" \
    "$D" "$CG" "$1" "$CE" "$1" "$N"
}

grade_one(){
  local n="$1"
  if check "$n"; then
    printf "  %s✔%s  %2s  %-3s pts   %s\n" "$G" "$N" "$n" "${PTS[$n]}" "correct"
    return 0
  else
    printf "  %s✘%s  %2s  %-3s pts   %s\n" "$R" "$N" "$n" "0" "unsolved or incomplete"
    return 1
  fi
}

grade_all(){
  local got=0 max=0 i
  printf "\n%s  Results · exam 2%s\n\n" "$BO" "$N"
  for i in $(seq 1 $TOTAL); do
    max=$(( max + ${PTS[$i]} ))
    if grade_one "$i"; then got=$(( got + ${PTS[$i]} )); fi
  done
  local pct=$(( got * 100 / max ))
  printf "\n  %sSCORE: %s/%s  (%s%%)%s   " "$BO" "$got" "$max" "$pct" "$N"
  if [ "$pct" -ge 66 ]; then printf "%sPASS%s\n\n" "$G$BO" "$N"
  else printf "%sFAIL%s %s(the CKA pass mark is 66)%s\n\n" "$R$BO" "$N" "$D" "$N"; fi
}

usage(){
  printf "\n%s  cka-helm-practice · exam 2%s — %s Helm tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sRepo management, values files and precedence, --atomic, subcharts,%s\n" "$D" "$N"
  printf "  %schart debugging. Exam 1 covers different ground; both can run at once.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-20s %s\n" "$CL"        "list every task with its points and status"
  printf "    %-20s %s\n" "$CQ N"      "show task N"
  printf "    %-20s %s\n" "$CG"        "grade everything and print the score"
  printf "    %-20s %s\n" "$CG N"      "grade task N only"
  printf "    %-20s %s\n" "$CE N"      "step-by-step walkthrough, with the reasoning"
  printf "    %-20s %s\n" "$CS N"      "just the commands, no explanation"
  printf "    %-20s %s\n" "$CH"        "this text"
  printf "    %-20s %s\n" "$CL version" "print the exam suite version"
  printf "    %-20s %s\n\n" "$CL reset" "re-seed exam 2 from scratch"
  if [ -n "${EXAM_HOME:-}" ]; then
    printf "%s  TAB COMPLETION%s\n\n" "$BO" "$N"
    printf "    q2, grade2, explain2 and solve2 complete task numbers with Tab.\n\n"
  else
    printf "%s  SHORTER COMMANDS%s\n\n" "$BO" "$N"
    printf "    Load the shell functions once and drop the './exam2.sh' prefix:\n\n"
    printf "      source %s/activate.sh\n\n" "$HERE"
    printf "    Then: %sexam2%s, %sq2 4%s, %sgrade2%s, %sexplain2 4%s from any directory.\n\n" \
      "$BO" "$N" "$BO" "$N" "$BO" "$N" "$BO" "$N"
  fi
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    Task 1 registers the chart repo that tasks 2, 3, 5, 8 and 10 install\n"
  printf "    from. Do it first or most of the exam is impossible.\n"
  printf "    Task 3 comes before 4 and 6 (they act on the release it creates).\n"
  printf "    Task 11 comes before 13: task 13 destroys what 11 asks you to find.\n"
  printf "    Task 5 creates the namespace task 12 installs into.\n\n"
  printf "%s  HOW IT WORKS%s\n\n" "$BO" "$N"
  printf "    Answers are the cluster's actual state. Some tasks want a file\n"
  printf "    instead; those say so and live in %s/\n" "$ANS"
  printf "    Working charts and values files are in %s/\n\n" "$EX2"
  printf "    %sIf the Killercoda session expires, run %s/setup2.sh again.%s\n\n" "$D" "$HERE" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Helm exam 2 for the CKA%s — %s tasks · 100 points · pass mark 66\n\n" "$BO" "$N" "$TOTAL"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   %s%s\n\n" "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show)
    need_n "${2:-}" "$CQ"; show "$2" ;;
  grade)
    if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"
    else grade_all; fi ;;
  solve)
    need_n "${2:-}" "$CS"
    printf "\n%s  Solution to exam 2, task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps)
    need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 2 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  reset) bash "$HERE/setup2.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s (exam 2)\n" "$VERSION" ;;
  *)
    printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"
    usage; exit 1 ;;
esac
