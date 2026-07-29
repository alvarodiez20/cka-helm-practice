#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam.sh
#  13 CKA-style Helm tasks. 100 points. Pass mark: 66.
#
#    ./exam.sh            list the tasks
#    ./exam.sh q 4        show task 4
#    ./exam.sh grade      grade everything, print the score
#    ./exam.sh grade 4    grade task 4 only
#    ./exam.sh solve 4    the commands that solve task 4
#    ./exam.sh explain 4  step-by-step walkthrough of task 4
#    ./exam.sh help       full usage
#    ./exam.sh version    print the exam suite version
#    ./exam.sh reset      re-seed the cluster (runs setup.sh)
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers"
REPO_NAME="ckarepo"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

# When activate.sh is loaded the commands are 'q 1' / 'grade';
# otherwise they have to go through the script.
if [ -n "${EXAM_HOME:-}" ]; then P=""; else P="./exam.sh "; fi

TOTAL=13
# Plain indexed arrays: every key is an integer, so this works on
# bash 3.2 as well as bash 5 (no 'declare -A' needed).
Q=(); PTS=(); SOL=(); WALK=()

Q[1]="The 'frontend' application must be deployed into the namespace 'web', which
DOES NOT EXIST YET. Install it from the chart ${REPO_NAME}/demo-app at version
0.2.0, with 3 replicas.
The release must be named exactly 'frontend'."
PTS[1]=7
SOL[1]="helm install frontend ${REPO_NAME}/demo-app --version 0.2.0 \\
  -n web --create-namespace --set replicaCount=3"
WALK[1]="1. Check which chart versions the repo actually offers, so you know 0.2.0
   is really there and you are not about to install something else:

     helm search repo ${REPO_NAME}/demo-app --versions

2. Confirm the namespace is missing. This matters: 'helm install -n web'
   FAILS if the namespace does not exist, it does not create it for you.

     kubectl get ns web        # Error ... not found

3. Install. Three requirements are being tested at once here, and each maps
   to one flag:

     --version 0.2.0      pin the chart version (without it you get the
                          newest one, 0.3.0, and the task fails)
     --create-namespace   create 'web' as part of the install
     --set replicaCount=3 override the chart's default replica count

     helm install frontend ${REPO_NAME}/demo-app --version 0.2.0 \\
       -n web --create-namespace --set replicaCount=3

4. Verify before moving on:

     helm list -n web                    # STATUS deployed, CHART demo-app-0.2.0
     kubectl get deploy -n web           # READY 3/3
     helm get values frontend -n web     # replicaCount: 3

Common traps: creating the namespace by hand with 'kubectl create ns web' is
also perfectly valid, just slower. Forgetting --version is the usual reason
this one scores zero."

Q[2]="The release 'legacy' in namespace 'apps' was upgraded by mistake to an image
that does not exist, and its pods will not start.
Return it to the last revision that DID work, using Helm's history.
Do not reinstall it and do not delete it."
PTS[2]=8
SOL[2]="helm history legacy -n apps          # find the last good revision (2)
helm rollback legacy 2 -n apps
# or, since it is the immediately previous one:
helm rollback legacy -n apps"
WALK[2]="1. See the damage first. Never roll back blind:

     helm list -n apps
     kubectl get pods -n apps        # ImagePullBackOff / ErrImagePull

2. Read the history. This is the whole point of the task: Helm keeps every
   revision, so recovery does not need the chart or the original values.

     helm history legacy -n apps

   You will see 3 revisions. The DESCRIPTION column tells you which ones
   succeeded; revision 3 is the broken upgrade, revision 2 is the last
   healthy one.

3. Roll back to it:

     helm rollback legacy 2 -n apps

   Because revision 2 happens to be the immediately preceding one, plain
   'helm rollback legacy -n apps' does the same thing. Being explicit is
   the better habit.

4. Verify:

     helm history legacy -n apps     # a NEW revision 4, 'Rollback to 2'
     kubectl get pods -n apps        # Running
     helm get values legacy -n apps  # the bad tag is gone

Key idea: a rollback does not erase revision 3, it appends a revision 4 whose
content equals revision 2. That is why the grader expects revision >= 4 and
not revision 2.

Common traps: 'helm uninstall' + 'helm install' looks like it fixes the pods,
but it destroys the history the task told you to use, and it fails the check."

Q[3]="A release called 'ghost' exists somewhere in the cluster, but you do not know
which namespace it is in.
Find out, and write ONLY the namespace name into the file
${ANS}/q3.txt"
PTS[3]=6
SOL[3]="helm list -A | grep ghost
echo hidden-77 > ${ANS}/q3.txt"
WALK[3]="1. 'helm list' on its own only looks at ONE namespace (the current context's,
   usually 'default'), which is exactly why the release seems to be missing.
   Search the whole cluster with -A (short for --all-namespaces):

     helm list -A

   Or go straight to it:

     helm list -A | grep ghost

   The NAMESPACE column shows 'hidden-77'.

2. Write just the namespace name into the answer file. No extra words, no
   YAML, no quotes; the grader strips whitespace and compares the string:

     echo hidden-77 > ${ANS}/q3.txt

3. Verify:

     cat ${ANS}/q3.txt

Worth knowing: Helm stores release state in Secrets inside the release's own
namespace, so 'kubectl get secrets -A | grep helm.release' is another way to
find a lost release when Helm itself is not cooperating.

Common traps: writing the whole 'helm list' line into the file instead of just
the namespace."

Q[4]="Upgrade the release 'frontend' to chart version 0.3.0, KEEPING the values it
already has configured (it must not lose its 3 replicas)."
PTS[4]=7
SOL[4]="helm upgrade frontend ${REPO_NAME}/demo-app --version 0.3.0 -n web --reuse-values
# passing --set replicaCount=3 again works too"
WALK[4]="1. Look at what the release currently overrides, so you know what there is
   to lose:

     helm get values frontend -n web     # replicaCount: 3

2. Upgrade, carrying those overrides across:

     helm upgrade frontend ${REPO_NAME}/demo-app --version 0.3.0 \\
       -n web --reuse-values

   --reuse-values means 'start from the values of the previous revision'.
   Without it, Helm starts from the chart defaults and your replicaCount=3
   silently drops back to the chart's default of 1.

3. Verify both halves of the task:

     helm list -n web                    # CHART demo-app-0.3.0
     helm get values frontend -n web     # replicaCount: 3 still there

Alternative: re-specifying everything explicitly is just as correct and is
arguably better practice in the real world, because it is not sensitive to
what the previous revision happened to contain:

     helm upgrade frontend ${REPO_NAME}/demo-app --version 0.3.0 \\
       -n web --set replicaCount=3

Do not confuse the flags: --reset-values throws the old values away and goes
back to chart defaults, which is the exact opposite of what is being asked."

Q[5]="Render into ${ANS}/q5.yaml the manifests that the chart
${REPO_NAME}/demo-app 0.3.0 would produce with replicaCount=5, WITHOUT
installing anything into the cluster and without modifying any existing
release."
PTS[5]=8
SOL[5]="helm template demo ${REPO_NAME}/demo-app --version 0.3.0 \\
  --set replicaCount=5 > ${ANS}/q5.yaml"
WALK[5]="1. 'helm template' renders a chart locally and prints the YAML to stdout. It
   never talks to the cluster's release state, which is what makes it the
   right tool when the task says 'without installing anything':

     helm template demo ${REPO_NAME}/demo-app --version 0.3.0 \\
       --set replicaCount=5 > ${ANS}/q5.yaml

   'demo' is the release name used for the name templating. Any name works;
   the grader does not care about it.

2. Verify the file really contains rendered manifests with 5 replicas:

     grep -e 'kind:' -e 'replicas:' ${ANS}/q5.yaml

3. Confirm you did not disturb the live release, which the grader also checks:

     helm get values frontend -n web     # still replicaCount: 3

Alternative: 'helm install demo ... --dry-run' produces similar output, but it
wraps the YAML in release metadata and it does contact the API server. For a
'render offline' task, 'helm template' is the canonical answer.

Common traps: running an 'upgrade' on 'frontend' with replicaCount=5 to get
the YAML out. That changes the live release and fails the second half of the
check."

Q[6]="Dump into ${ANS}/q6.txt ALL the values the release 'frontend' is
running with, including the chart defaults you never touched."
PTS[6]=7
SOL[6]="helm get values frontend -n web -a > ${ANS}/q6.txt"
WALK[6]="1. See the difference between the two forms first, because that difference IS
   the task:

     helm get values frontend -n web        # only what YOU supplied
     helm get values frontend -n web -a     # yours PLUS every chart default

   -a is short for --all. The plain form prints a handful of lines; the -a
   form prints the whole computed value set (image, pullPolicy, service,
   resources, serviceAccount, and so on).

2. Write the complete set to the file:

     helm get values frontend -n web -a > ${ANS}/q6.txt

3. Verify it contains the defaults, not just your overrides:

     grep -e replicaCount -e pullPolicy -e service ${ANS}/q6.txt

Common traps: omitting -a. The file then holds only replicaCount and the
image tag, the default keys are absent, and the check fails."

Q[7]="Remove the release 'ghost' from the cluster but KEEP its history, so that it
can be recovered later on."
PTS[7]=7
SOL[7]="helm uninstall ghost -n hidden-77 --keep-history"
WALK[7]="1. This is the namespace you found in task 3. Uninstall with the flag that
   preserves the release record:

     helm uninstall ghost -n hidden-77 --keep-history

2. Verify. The Kubernetes objects are gone, but Helm still knows the release
   existed and is now in state 'uninstalled':

     kubectl get all -n hidden-77            # nothing from the release
     helm list -n hidden-77                  # empty (only 'deployed' shown)
     helm list -n hidden-77 --uninstalled    # ghost, status uninstalled
     helm history ghost -n hidden-77         # history still readable

Read task 8 before you run anything here: a plain 'helm uninstall ghost
-n hidden-77' purges the release record entirely, which makes task 8
impossible and costs you both sets of points. There is no undo."

Q[8]="Recover the release 'ghost': it must be deployed again.
Do it from its history, without reinstalling it from the repository."
PTS[8]=8
SOL[8]="helm list -n hidden-77 --uninstalled     # see the last revision
helm rollback ghost -n hidden-77"
WALK[8]="1. Find what is left to work with. An uninstalled-but-kept release is
   invisible to a plain 'helm list':

     helm list -n hidden-77 --uninstalled
     helm history ghost -n hidden-77

2. Roll it back. 'helm rollback' works on an uninstalled release precisely
   because task 7 kept the history; with no argument it targets the previous
   revision:

     helm rollback ghost -n hidden-77

   Being explicit works too, e.g. 'helm rollback ghost 1 -n hidden-77'.

3. Verify it is genuinely live again:

     helm list -n hidden-77             # STATUS deployed
     helm history ghost -n hidden-77    # new revision on top
     kubectl get deploy,pod -n hidden-77

Common traps: 'helm install ghost ${REPO_NAME}/demo-app -n hidden-77' does
bring the workload back, but the task explicitly forbids reinstalling from the
repo, and it starts the revision count over at 1 while the grader expects
revision >= 3."

Q[9]="Create a brand-new chart called 'mychart' in ${BASE}/mychart.
The CHART version must be 1.2.0 and the APPLICATION version 3.4.5.
The chart must pass 'helm lint' with no errors."
PTS[9]=10
SOL[9]="cd ${BASE} && helm create mychart
sed -i 's/^version:.*/version: 1.2.0/' mychart/Chart.yaml
sed -i 's/^appVersion:.*/appVersion: \"3.4.5\"/' mychart/Chart.yaml
helm lint ./mychart"
WALK[9]="1. Scaffold the chart. 'helm create' writes a complete, working nginx-based
   chart, which is why this task is fast if you know the command:

     cd ${BASE}
     helm create mychart

2. Understand the two fields before editing them, because the task
   deliberately gives them different values:

     version     the version of the CHART itself       -> 1.2.0
     appVersion  the version of the APP inside it      -> 3.4.5

   Edit ${BASE}/mychart/Chart.yaml, either with vi or in place:

     sed -i 's/^version:.*/version: 1.2.0/' ${BASE}/mychart/Chart.yaml
     sed -i 's/^appVersion:.*/appVersion: \"3.4.5\"/' ${BASE}/mychart/Chart.yaml

   Keep appVersion quoted. It is a free-form string, and an unquoted value
   like 3.4.5 is fine here but the quoted form is what 'helm create' itself
   produces and it avoids surprises with values such as 1.25.

3. Lint it, which the task requires explicitly:

     helm lint ${BASE}/mychart

   Expect '1 chart(s) linted, 0 chart(s) failed'. An INFO line about the icon
   being recommended is not an error and is fine to leave.

4. Verify what you actually changed:

     grep -e '^version:' -e '^appVersion:' ${BASE}/mychart/Chart.yaml

Common traps: swapping the two versions round. The grader checks each field
separately, so a swap scores zero rather than half."

Q[10]="Package the chart 'mychart' and leave the resulting .tgz file inside the
directory ${BASE}/dist/"
PTS[10]=7
SOL[10]="mkdir -p ${BASE}/dist
helm package ${BASE}/mychart -d ${BASE}/dist"
WALK[10]="1. 'helm package' turns a chart directory into a versioned .tgz archive. -d
   chooses where the archive lands:

     mkdir -p ${BASE}/dist
     helm package ${BASE}/mychart -d ${BASE}/dist

   Note the filename is derived from Chart.yaml, not from you: because task 9
   set version to 1.2.0, you get 'mychart-1.2.0.tgz'. If your file comes out
   named differently, task 9 is not actually done.

2. Verify:

     ls -l ${BASE}/dist/

Worth knowing: -d creates the target directory if it is missing, so the mkdir
is belt and braces rather than strictly required.

Common traps: running 'helm package' with no -d, which drops the .tgz into the
current working directory instead."

Q[11]="Install the PACKAGED chart from the previous task as release 'mine' in the
namespace 'dev', which does not exist. The command must not return until the
resources are ready."
PTS[11]=8
SOL[11]="helm install mine ${BASE}/dist/mychart-1.2.0.tgz \\
  -n dev --create-namespace --wait"
WALK[11]="1. Helm installs from a local .tgz path exactly as it does from a repo
   reference; you just give it the file instead of 'repo/chart'. Each clause
   of the task is again one flag:

     the packaged chart     ${BASE}/dist/mychart-1.2.0.tgz
     namespace that is new  --create-namespace
     'must not return until ready'  --wait

     helm install mine ${BASE}/dist/mychart-1.2.0.tgz \\
       -n dev --create-namespace --wait

   --wait blocks until the pods are Ready rather than returning as soon as the
   objects are created. Note the command genuinely takes longer to come back;
   that is the flag working, not a hang. It gives up after 5 minutes by
   default, tunable with --timeout 2m.

2. Verify:

     helm list -n dev              # STATUS deployed, CHART mychart-1.2.0
     kubectl get pods -n dev       # Running

Common traps: pointing at the chart DIRECTORY (${BASE}/mychart) instead of the
packaged archive. The release deploys and looks healthy, but the task asked for
the packaged chart."

Q[12]="The release 'frontend' must switch to image tag 1.25, and Helm must store it
as a STRING, not as a number.
Apply the corresponding upgrade without losing the rest of its configuration."
PTS[12]=9
SOL[12]="helm upgrade frontend ${REPO_NAME}/demo-app -n web --reuse-values \\
  --set-string image.tag=1.25
# with --set image.tag=1.25 Helm stores a number and the check fails"
WALK[12]="1. The trap is YAML type coercion. '1.25' looks like text to you, but --set
   parses it and sees a valid float, so Helm stores the number 1.25. Image
   tags must be strings; a numeric tag can render as '1.25' today and bite
   you the day the tag is something like 1.30 (which YAML would happily
   normalise to 1.3).

   --set-string skips that parsing and always stores a string:

     helm upgrade frontend ${REPO_NAME}/demo-app -n web \\
       --reuse-values --set-string image.tag=1.25

   --reuse-values covers the 'without losing the rest of its configuration'
   half of the task, keeping replicaCount=3 and chart version 0.3.0.

2. Verify the TYPE, not just the value. This is the one check where reading
   plain YAML output is not enough, because YAML prints both the same way.
   JSON shows quotes around a string and none around a number:

     helm get values frontend -n web -o json

   You want '\"tag\":\"1.25\"' with the quotes. If you see '\"tag\":1.25' you
   used --set and need to redo the upgrade with --set-string.

3. Confirm nothing else was lost:

     helm list -n web                       # CHART still demo-app-0.3.0
     helm get values frontend -n web        # replicaCount still 3

Also valid: a values file with 'tag: \"1.25\"' quoted, passed with -f. The
quotes in the file do the same job as --set-string."

Q[13]="The chart ${BASE}/mychart must declare the chart 'demo-app' version 0.3.0
from the repository '${REPO_NAME}' as a dependency, and that dependency must be
downloaded inside the chart."
PTS[13]=8
SOL[13]="cat >> ${BASE}/mychart/Chart.yaml <<'EOF'
dependencies:
  - name: demo-app
    version: 0.3.0
    repository: http://127.0.0.1:8879
EOF
helm dependency update ${BASE}/mychart"
WALK[13]="1. Declare the dependency in Chart.yaml. It is a top-level 'dependencies'
   list, so append it at the end of the file, minding the indentation:

     cat >> ${BASE}/mychart/Chart.yaml <<'EOF'
     dependencies:
       - name: demo-app
         version: 0.3.0
         repository: http://127.0.0.1:8879
     EOF

   (If you paste that by hand, drop the leading spaces shown above; the
   heredoc body must start at column 0.)

   For 'repository' you can use the URL as above, or the repo alias form
   '\"@${REPO_NAME}\"'. Both resolve to the local chart server this exam runs
   on 127.0.0.1:8879.

2. Download it. Declaring is not enough, the task says it must be downloaded:

     helm dependency update ${BASE}/mychart

3. Verify the archive landed in the chart's charts/ subdirectory, and that
   Helm agrees the dependency is satisfied:

     ls ${BASE}/mychart/charts/          # demo-app-0.3.0.tgz
     helm dependency list ${BASE}/mychart  # STATUS ok

Know the difference between the two subcommands, it is a classic exam
question:

     helm dependency update   re-resolves Chart.yaml and rewrites Chart.lock
     helm dependency build    installs exactly what Chart.lock already pins,
                              and fails if there is no lock file yet

Since this chart has no Chart.lock, 'update' is the one that works."

# ─────────── grading helpers ───────────
hfield(){ # release ns field -> value
  helm list -n "$2" --filter "^$1\$" -o json 2>/dev/null \
    | tr '{},' '\n' | grep "\"$3\":" | head -1 | cut -d'"' -f4
}
hnum(){ local v; v="$(hfield "$1" "$2" "$3")"; echo "${v:-0}"; }
huninstalled(){ helm list -n "$2" --uninstalled -o json 2>/dev/null | grep -q "\"$1\""; }
hvals(){ helm get values "$1" -n "$2" ${3:-} -o json 2>/dev/null; }
nsexists(){ kubectl get ns "$1" >/dev/null 2>&1; }
filehas(){ [ -f "$1" ] && grep -q "$2" "$1"; }

check(){
  case "$1" in
    1) nsexists web \
       && [ "$(hfield frontend web status)" = "deployed" ] \
       && hvals frontend web | grep -q '"replicaCount":3' \
       && helm history frontend -n web -o json 2>/dev/null | grep -q 'demo-app-0.2.0' ;;
    2) [ "$(hfield legacy apps status)" = "deployed" ] \
       && [ "$(hnum legacy apps revision)" -ge 4 ] \
       && ! hvals legacy apps | grep -q 'does-not-exist-tag' ;;
    3) [ -f "$ANS/q3.txt" ] \
       && [ "$(tr -d '[:space:]' < "$ANS/q3.txt")" = "hidden-77" ] ;;
    4) [ "$(hfield frontend web chart)" = "demo-app-0.3.0" ] \
       && hvals frontend web | grep -q '"replicaCount":3' ;;
    5) filehas "$ANS/q5.yaml" "kind: Deployment" \
       && filehas "$ANS/q5.yaml" "replicas: 5" \
       && hvals frontend web | grep -q '"replicaCount":3' ;;
    6) filehas "$ANS/q6.txt" "replicaCount" \
       && filehas "$ANS/q6.txt" "pullPolicy" \
       && filehas "$ANS/q6.txt" "service" ;;
    7) helm history ghost -n hidden-77 -o json 2>/dev/null | grep -q 'uninstalled' ;;
    8) [ "$(hfield ghost hidden-77 status)" = "deployed" ] \
       && [ "$(hnum ghost hidden-77 revision)" -ge 3 ] ;;
    9) [ -f "$BASE/mychart/Chart.yaml" ] \
       && grep -Eq '^version:[[:space:]]*1\.2\.0[[:space:]]*$' "$BASE/mychart/Chart.yaml" \
       && grep -Eq '^appVersion:[[:space:]]*"?3\.4\.5"?[[:space:]]*$' "$BASE/mychart/Chart.yaml" \
       && helm lint "$BASE/mychart" >/dev/null 2>&1 ;;
    10) ls "$BASE"/dist/mychart-1.2.0.tgz >/dev/null 2>&1 ;;
    11) nsexists dev \
       && [ "$(hfield mine dev status)" = "deployed" ] \
       && [ "$(hfield mine dev chart)" = "mychart-1.2.0" ] ;;
    12) hvals frontend web | grep -q '"tag":"1.25"' ;;
    13) grep -q 'demo-app' "$BASE/mychart/Chart.yaml" 2>/dev/null \
       && ls "$BASE"/mychart/charts/demo-app-0.3.0.tgz >/dev/null 2>&1 ;;
    *) return 2 ;;
  esac
}

valid_n(){ # numeric and within 1..TOTAL
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]
}

need_n(){ # validate an argument, or explain and exit
  if ! valid_n "${1:-}"; then
    printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s%s 4\n\n" \
      "$R" "$TOTAL" "$N" "$P" "${2:-q}" >&2
    exit 1
  fi
}

show(){
  printf "\n%s┌─ Task %s/%s ─ %s points%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N"
  printf "%s└%s\n" "$B" "$N"
  echo "${Q[$1]}"
  printf "\n%s  when you are done:  %sgrade %s      stuck?  %sexplain %s%s\n\n" \
    "$D" "$P" "$1" "$P" "$1" "$N"
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
  printf "\n%s  Results%s\n\n" "$BO" "$N"
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
  printf "\n%s  cka-helm-practice%s — %s Helm tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sYou solve them against a real cluster; grading inspects real state.%s\n\n" "$D" "$N"
  # Listing is 'exam' once activated, but a bare './exam.sh' otherwise.
  local list_cmd; if [ -z "$P" ]; then list_cmd="exam"; else list_cmd="./exam.sh"; fi
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-20s %s\n" "$list_cmd"      "list every task with its points and status"
  printf "    %-20s %s\n" "${P}q N"        "show task N"
  printf "    %-20s %s\n" "${P}grade"      "grade everything and print the score"
  printf "    %-20s %s\n" "${P}grade N"    "grade task N only"
  printf "    %-20s %s\n" "${P}explain N"  "step-by-step walkthrough, with the reasoning"
  printf "    %-20s %s\n" "${P}solve N"    "just the commands, no explanation"
  printf "    %-20s %s\n" "${P}help"       "this text"
  printf "    %-20s %s\n" "${P}version"    "print the exam suite version"
  printf "    %-20s %s\n\n" "${P}reset"    "re-seed the cluster from scratch"
  if [ -z "$P" ]; then
    printf "%s  TAB COMPLETION%s\n\n" "$BO" "$N"
    printf "    q, grade, explain and solve complete task numbers with Tab.\n\n"
  else
    printf "%s  SHORTER COMMANDS%s\n\n" "$BO" "$N"
    printf "    Load the shell functions once and drop the './exam.sh' prefix:\n\n"
    printf "      source %s/activate.sh\n\n" "$HERE"
    printf "    Then: %sexam%s, %sq 4%s, %sgrade%s, %sexplain 4%s from any directory.\n\n" \
      "$BO" "$N" "$BO" "$N" "$BO" "$N" "$BO" "$N"
  fi
  printf "%s  HOW IT WORKS%s\n\n" "$BO" "$N"
  printf "    Answers are the cluster's actual state. A few tasks want a file\n"
  printf "    instead; those say so and live in %s/\n" "$ANS"
  printf "    Tasks 7 and 8 are a pair: read 8 before you run 7.\n"
  printf "    Tasks 9, 10, 11 and 13 build on each other in that order.\n\n"
  printf "    %sIf the Killercoda session expires, run %s/setup.sh again.%s\n\n" "$D" "$HERE" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Helm exam for the CKA%s — %s tasks · 100 points · pass mark 66\n\n" "$BO" "$N" "$TOTAL"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%sq N   ·   %sgrade   ·   %sexplain N   ·   %shelp%s\n\n" "$D" "$P" "$P" "$P" "$P" "$N" ;;
  q|show)
    need_n "${2:-}" q; show "$2" ;;
  grade)
    if [ $# -ge 2 ]; then need_n "$2" grade; printf "\n"; grade_one "$2"; printf "\n"
    else grade_all; fi ;;
  solve)
    need_n "${2:-}" solve
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %sexplain %s%s\n\n" "$D" "$P" "$2" "$N" ;;
  explain|walk|steps)
    need_n "${2:-}" explain
    printf "\n%s┌─ Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %sgrade %s%s\n\n" "$D" "$P" "$2" "$N" ;;
  reset) bash "$HERE/setup.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s (exam 1)\n" "$VERSION" ;;
  *)
    printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"
    usage; exit 1 ;;
esac
