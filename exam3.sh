#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam3.sh
#  13 CKA-style Helm tasks against REAL public charts and a
#  real OCI registry. 100 points. Pass mark: 66.
#
#    ./exam3.sh            list the tasks
#    ./exam3.sh q 4        show task 4
#    ./exam3.sh grade      grade everything, print the score
#    ./exam3.sh grade 4    grade task 4 only
#    ./exam3.sh solve 4    the commands that solve task 4
#    ./exam3.sh explain 4  step-by-step walkthrough of task 4
#    ./exam3.sh help       full usage
#    ./exam3.sh version    print the exam suite version
#    ./exam3.sh reset      re-seed the cluster (runs setup3.sh)
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers3"
EX3="$BASE/exam3"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"

ARGO_URL="https://argoproj.github.io/argo-helm"
TRAEFIK_URL="https://traefik.github.io/charts"
NGINX_URL="https://kubernetes.github.io/ingress-nginx"
PODINFO_URL="https://stefanprodan.github.io/podinfo"
PODINFO_OCI="oci://ghcr.io/stefanprodan/charts/podinfo"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

# The command names differ depending on whether activate.sh is loaded.
if [ -n "${EXAM_HOME:-}" ]; then
  CL="exam3"; CQ="q3"; CG="grade3"; CE="explain3"; CS="solve3"; CH="exam3help"
else
  CL="./exam3.sh"; CQ="./exam3.sh q"; CG="./exam3.sh grade"
  CE="./exam3.sh explain"; CS="./exam3.sh solve"; CH="./exam3.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

# ─────────────────────────── 1 ───────────────────────────
Q[1]="The Argo Helm repository must be registered locally under the name 'argo',
pointing at ${ARGO_URL}, and its index must be
cached so that 'helm search repo argo/argo-cd' finds the chart."
PTS[1]=6
SOL[1]="helm repo add argo ${ARGO_URL}
helm repo update argo
helm search repo argo/argo-cd --versions | head"
WALK[1]="1. Nothing is pre-configured in this exam — check what you actually have:

     helm repo list

   On a fresh cluster this prints 'no repositories to show'. That is not an
   error, it is the starting point.

2. Add the repository. The name is the local alias; from then on charts are
   addressed as '<alias>/<chart>':

     helm repo add argo ${ARGO_URL}

   'helm repo add' already downloads index.yaml, so in practice the repo is
   usable immediately. 'helm repo update' re-downloads it, which is what you
   want when the repo has published something since you added it:

     helm repo update argo        # just this one
     helm repo update             # every configured repo

3. Verify by finding the chart, not by trusting the add:

     helm repo list                              # argo + the URL
     helm search repo argo/argo-cd --versions     # many versions listed

Common traps: 'helm search hub' searches Artifact Hub over the internet and
has nothing to do with your local repos — if a task says 'the repository you
added', it means 'helm search repo'. Also note that repo config is per-user
(~/.config/helm/repositories.yaml), so adding it as root does not add it for
another user."

# ─────────────────────────── 2 ───────────────────────────
Q[2]="Render — do NOT install — the chart argo/argo-cd at chart version 7.9.1 for
the namespace 'argocd', and write the result to ${ANS}/q2.yaml.
The rendered output must not contain a single CustomResourceDefinition."
PTS[2]=9
SOL[2]="helm template argocd argo/argo-cd --version 7.9.1 -n argocd \\
  --set crds.install=false > ${ANS}/q2.yaml
# NOT --skip-crds: this chart renders its CRDs from templates/, so
# --skip-crds has no effect on it whatsoever."
WALK[2]="1. Render it the obvious way first, and count what you got:

     helm template argocd argo/argo-cd --version 7.9.1 -n argocd \\
       | grep -c 'kind: CustomResourceDefinition'
     # 3

2. Now the trap, and it is the whole point of the task. Everyone reaches for
   --skip-crds. Try it:

     helm template argocd argo/argo-cd --version 7.9.1 -n argocd --skip-crds \\
       | grep -c 'kind: CustomResourceDefinition'
     # still 3

   --skip-crds only suppresses files in the chart's special crds/ directory.
   The Argo CD chart does not use crds/ — it keeps its CRDs in
   templates/crds/, guarded by a value. To Helm they are ordinary templates,
   so no CRD flag touches them.

   Confirm where the value lives instead of guessing:

     helm show values argo/argo-cd --version 7.9.1 | grep -n -A3 '^crds:'
     # crds:
     #   install: true

3. So the correct answer is the chart's own value:

     helm template argocd argo/argo-cd --version 7.9.1 -n argocd \\
       --set crds.install=false > ${ANS}/q2.yaml

4. Verify:

     grep -c 'kind: CustomResourceDefinition' ${ANS}/q2.yaml   # 0
     grep -c 'kind: Deployment' ${ANS}/q2.yaml                 # non-zero

The general rule worth memorising: crds/ directory → --skip-crds works;
CRDs in templates/ → find the chart's value with 'helm show values'. Check
which kind of chart you have before choosing the flag."

# ─────────────────────────── 3 ───────────────────────────
Q[3]="Install argo/argo-cd at chart version 7.9.1 as the release 'argocd' into the
namespace 'argocd', WHICH DOES NOT EXIST YET.
Argo CD's CustomResourceDefinitions must not end up in the cluster — another
team owns them. Do not wait for the pods to become ready."
PTS[3]=8
SOL[3]="helm install argocd argo/argo-cd --version 7.9.1 \\
  -n argocd --create-namespace --set crds.install=false"
WALK[3]="1. Same CRD reasoning as task 2, now on the install side. --skip-crds would
   again do nothing here, so the value is what matters:

     helm install argocd argo/argo-cd --version 7.9.1 \\
       -n argocd --create-namespace --set crds.install=false

   Three requirements, three pieces:

     --version 7.9.1        pin the chart (without it you get the newest)
     --create-namespace     'argocd' does not exist; helm install -n does
                            NOT create it for you
     --set crds.install=false   keep the CRDs out of the cluster

2. No --wait, deliberately. The task says not to wait, and on a small
   practice cluster Argo CD takes minutes to settle. Without --wait the
   release goes straight to 'deployed' once the objects are created — which
   is what the grader checks.

3. Verify, and specifically verify the CRDs are absent:

     helm list -n argocd                      # STATUS deployed, argo-cd-7.9.1
     kubectl get crd | grep argoproj          # nothing
     kubectl get deploy -n argocd             # objects exist, may be 0/1

Common traps: uninstalling later will not remove CRDs even when Helm did
install them — Helm never deletes CRDs on uninstall, which is exactly why
production setups manage them separately, and why this task exists."

# ─────────────────────────── 4 ───────────────────────────
Q[4]="Register the Traefik chart repository as 'traefik' (${TRAEFIK_URL}),
then write the manifests of chart version 34.2.0 to ${ANS}/q4.yaml.
The output MUST include the chart's CustomResourceDefinitions.
Nothing may be installed into the cluster."
PTS[4]=7
SOL[4]="helm repo add traefik ${TRAEFIK_URL}
helm template traefik traefik/traefik --version 34.2.0 \\
  --include-crds > ${ANS}/q4.yaml"
WALK[4]="1. Add the repo, then render it naively and count:

     helm repo add traefik ${TRAEFIK_URL}
     helm template traefik traefik/traefik --version 34.2.0 \\
       | grep -c 'kind: CustomResourceDefinition'
     # 0

   Zero — even though this chart definitely ships CRDs. This is the mirror
   image of task 2, and just as commonly misunderstood.

2. Traefik keeps its CRDs in the chart's crds/ directory. Prove it:

     helm pull traefik/traefik --version 34.2.0 --untar --untardir /tmp/tk
     ls /tmp/tk/traefik/         # Chart.yaml  crds  templates  values.yaml

   'helm install' applies crds/ automatically. 'helm template' does NOT
   render it, because template output is normally meant to be piped into
   kubectl apply, and Helm treats CRDs as a separate lifecycle.

3. --include-crds is the flag that adds them back:

     helm template traefik traefik/traefik --version 34.2.0 \\
       --include-crds > ${ANS}/q4.yaml

4. Verify — and check you did not install anything:

     grep -c 'kind: CustomResourceDefinition' ${ANS}/q4.yaml   # 26
     helm list -A                                             # no traefik

Put tasks 2 and 4 side by side and the whole CRD flag family makes sense:

     helm template            crds/ omitted
     helm template --include-crds     crds/ rendered
     helm install             crds/ applied automatically
     helm install --skip-crds crds/ skipped
     CRDs in templates/       no flag helps; use the chart's own value"

# ─────────────────────────── 5 ───────────────────────────
Q[5]="Register the ingress-nginx repository as 'ingress-nginx' (${NGINX_URL}).
Write into ${ANS}/q5.txt — and nothing else — the APPLICATION version
that chart version 4.12.0 of ingress-nginx/ingress-nginx ships."
PTS[5]=6
SOL[5]="helm repo add ingress-nginx ${NGINX_URL}
helm show chart ingress-nginx/ingress-nginx --version 4.12.0 | grep appVersion
echo 1.12.0 > ${ANS}/q5.txt"
WALK[5]="1. Add the repo:

     helm repo add ingress-nginx ${NGINX_URL}

2. Two different versions live in every chart and the exam loves the
   distinction:

     version      the chart's own version — the packaging
     appVersion   the version of the software the chart deploys

   Here the chart is 4.12.0 and the app it installs is nginx ingress
   controller 1.12.0. They look alike in this chart, which is precisely why
   reading it rather than assuming it matters.

3. Read it without downloading or installing anything:

     helm show chart ingress-nginx/ingress-nginx --version 4.12.0

   That prints Chart.yaml. Pull out the one line:

     helm show chart ingress-nginx/ingress-nginx --version 4.12.0 \\
       | grep '^appVersion'
     # appVersion: 1.12.0

   'helm search repo ingress-nginx/ingress-nginx --versions' shows the same
   pairing in a table, if you prefer the overview.

4. The answer file must hold the version and nothing else:

     echo 1.12.0 > ${ANS}/q5.txt
     cat ${ANS}/q5.txt

Related subcommands worth knowing, all of which work without installing:

     helm show chart      Chart.yaml
     helm show values     values.yaml
     helm show readme     README.md
     helm show all        all of the above"

# ─────────────────────────── 6 ───────────────────────────
Q[6]="The release 'web' must run chart podinfo 6.7.0 from the repository 'podinfo'
(${PODINFO_URL}) in the namespace 'demo', which does
not exist yet, with 2 replicas and a service of type NodePort.
The overrides must come from a values file that you write at
${EX3}/web-values.yaml — not from --set."
PTS[6]=8
SOL[6]="helm repo add podinfo ${PODINFO_URL}
cat > ${EX3}/web-values.yaml <<'EOF'
replicaCount: 2
service:
  type: NodePort
EOF
helm install web podinfo/podinfo --version 6.7.0 \\
  -n demo --create-namespace -f ${EX3}/web-values.yaml"
WALK[6]="1. Add the repo, then find out what the keys are actually called. Do not
   invent them — 'replicas' and 'serviceType' both look plausible and both
   are wrong for this chart:

     helm repo add podinfo ${PODINFO_URL}
     helm show values podinfo/podinfo --version 6.7.0 | head -30

   You will see 'replicaCount' at the top level and 'type' nested under
   'service'.

2. Write the values file. Nesting in YAML is what '--set service.type=...'
   expresses with dots:

     cat > ${EX3}/web-values.yaml <<'EOF'
     replicaCount: 2
     service:
       type: NodePort
     EOF

   (Typing that by hand: drop the leading spaces shown above, the heredoc
   body starts at column 0.)

3. Install, pointing at the file with -f (long form --values):

     helm install web podinfo/podinfo --version 6.7.0 \\
       -n demo --create-namespace -f ${EX3}/web-values.yaml

4. Verify both the file and what Helm stored from it:

     helm list -n demo                    # deployed, podinfo-6.7.0
     helm get values web -n demo          # replicaCount: 2, type: NodePort
     kubectl get svc -n demo              # TYPE NodePort
     kubectl get deploy -n demo           # 2 replicas

Why a file rather than --set: it is reviewable, diffable and committable, and
it is what the exam means by 'a values file'. --set would produce an
identical release, and would still fail a task worded like this one."

# ─────────────────────────── 7 ───────────────────────────
Q[7]="Install the podinfo chart again, this time at version 6.9.0 and straight from
its OCI registry at ${PODINFO_OCI},
as the release 'oci-web' in the namespace 'demo'.
No chart repository may be involved."
PTS[7]=8
SOL[7]="helm install oci-web ${PODINFO_OCI} \\
  --version 6.9.0 -n demo"
WALK[7]="1. An OCI reference replaces the '<repo>/<chart>' argument entirely. There
   is no 'helm repo add' step, because an OCI registry has no index.yaml —
   you address a chart by its full path:

     helm show chart ${PODINFO_OCI} --version 6.9.0

   Note that --version is effectively mandatory with OCI: the registry has
   no index to search, so Helm resolves the tag you name (it falls back to
   the 'latest'-style newest tag, which is not something to rely on in an
   exam).

2. Install it. The namespace already exists from task 6, so no
   --create-namespace this time:

     helm install oci-web ${PODINFO_OCI} \\
       --version 6.9.0 -n demo

3. Verify:

     helm list -n demo            # web AND oci-web, podinfo-6.9.0
     helm repo list               # no new repo was added — as required

Worth knowing around OCI, because the CKA has moved this way:

     helm registry login ghcr.io -u USER      private registries
     helm push mychart-1.0.0.tgz oci://ghcr.io/me/charts
     helm pull oci://.../podinfo --version 6.9.0

Common traps: writing 'oci://ghcr.io/stefanprodan/charts' and expecting Helm
to find podinfo inside it. The chart name is part of the URL, not an
argument after it."

# ─────────────────────────── 8 ───────────────────────────
Q[8]="Move the release 'web' in namespace 'demo' to chart version 6.9.0.
Its 2 replicas and its NodePort service must survive the upgrade WITHOUT you
restating them — not on the command line, not with a values file."
PTS[8]=8
SOL[8]="helm upgrade web podinfo/podinfo --version 6.9.0 -n demo --reuse-values"
WALK[8]="1. See what Helm is currently holding for the release, since that is what
   has to be preserved:

     helm get values web -n demo
     # replicaCount: 2
     # service:
     #   type: NodePort

2. A plain 'helm upgrade' throws all of that away and reverts to the chart's
   defaults — one replica, ClusterIP. --reuse-values carries the previous
   user-supplied values into the new revision:

     helm upgrade web podinfo/podinfo --version 6.9.0 -n demo --reuse-values

3. Verify the version moved and the values did not:

     helm list -n demo                 # CHART podinfo-6.9.0
     helm get values web -n demo       # replicaCount 2, NodePort intact
     helm history web -n demo          # revision 2, 'Upgrade complete'

Know the three related flags, they are easy exam points:

     --reuse-values               keep old values, apply any new --set on top
     --reset-values               discard old values, use chart defaults
     --reset-then-reuse-values    chart defaults, then re-apply old values —
                                  the one you want when the new chart version
                                  has changed its own defaults

Common traps: --reuse-values also pins you to values that may no longer
exist in the newer chart. When an upgrade fails right after you used it,
that is the first thing to suspect."

# ─────────────────────────── 9 ───────────────────────────
Q[9]="A release somewhere in this cluster is stuck in 'pending-install': it holds its
name and blocks any reinstall under that name, and on Helm 3 the default
listing will not even show it.
Find it and remove it completely — no release record may survive."
PTS[9]=8
SOL[9]="helm list -A --pending               # 'stuck-report' in limbo, pending-install
helm uninstall stuck-report -n limbo"
WALK[9]="1. Which listing shows it depends on your Helm major version, and this is
   worth knowing cold because the CKA now ships Helm 4:

     Helm 3   'helm list' shows only deployed and failed releases. States
              like pending-install, pending-upgrade and uninstalling are
              hidden until you pass -a/--all.
     Helm 4   'helm list' shows EVERY status by default, and -a/--all was
              removed. Passing it is a hard error:
                Error: unknown shorthand flag: 'a' in -a

   So the portable move is neither -a nor the bare default — it is the
   status filter, which exists in both:

     helm list -A --pending
     # NAME          NAMESPACE  REVISION  STATUS
     # stuck-report  limbo      1         pending-install

   -A is --all-namespaces. Without it you are searching one namespace.

2. pending-install means an install was interrupted — the process died
   between writing the release record and finishing. There is nothing to
   roll back to, so the fix is to remove the record:

     helm uninstall stuck-report -n limbo

3. Verify it is really gone, not merely hidden. The release Secret is the
   ground truth, independent of what 'helm list' decides to display:

     helm list -A --pending                              # no output
     kubectl get secret -n limbo | grep sh.helm.release   # no output

Know the shape of the underlying object: every revision is a Secret named
sh.helm.release.v1.<release>.v<n>. Deleting those Secrets by hand is the
last-resort fix people reach for when even 'helm uninstall' refuses, and
knowing where the state lives is what the question is really testing.

Common traps: 'helm rollback' on a pending-install has nothing to roll back
to and fails. And a release stuck in pending-UPGRADE is the opposite case —
there you roll back to the last good revision rather than uninstalling."

# ─────────────────────────── 10 ───────────────────────────
Q[10]="Write into ${ANS}/q10.txt the Kubernetes resources that Helm itself
considers part of the release 'oci-web' in the namespace 'demo'.
Use Helm's own status output, not kubectl."
PTS[10]=8
SOL[10]="helm status oci-web -n demo > ${ANS}/q10.txt     # Helm 4: resources included
# On Helm 3 the resources section is opt-in:
#   helm status oci-web -n demo --show-resources > ${ANS}/q10.txt"
WALK[10]="1. Check which Helm you are on first, because this is the third command in
   this exam whose Helm 3 flag became the Helm 4 default:

     helm version --short

     Helm 3   'helm status' prints only the header — revision, last deployed,
              status, notes. The object list is opt-in via --show-resources.
     Helm 4   the RESOURCES section is always included, and --show-resources
              was REMOVED. Passing it errors:
                Error: unknown flag: --show-resources

2. So run whichever your version wants:

     helm status oci-web -n demo                     # Helm 4
     helm status oci-web -n demo --show-resources    # Helm 3

   Either way you get the objects grouped by API version and kind, with the
   readiness columns kubectl would give you:

     # RESOURCES:
     # ==> v1/Service
     # NAME             TYPE       CLUSTER-IP    PORT(S)
     # oci-web-podinfo  ClusterIP  10.99.17.165  9898/TCP,9999/TCP
     #
     # ==> v1/Deployment
     # NAME             READY  UP-TO-DATE  AVAILABLE
     # oci-web-podinfo  1/1    1           1
     #
     # ==> v1/Pod(related)

3. Redirect it:

     helm status oci-web -n demo > ${ANS}/q10.txt
     cat ${ANS}/q10.txt

Two neighbouring commands, and knowing which one a task wants is the skill:

     helm status <r> --show-resources   live objects, with readiness
     helm get manifest <r>              the YAML Helm applied, as applied
     helm get all <r>                   manifest + values + hooks + notes

'--show-resources' answers 'what is running'; 'get manifest' answers 'what
did Helm send'. When they disagree, something changed the objects outside
Helm — which is the actual diagnostic value of comparing them.

Also useful: 'helm status <r> --revision 2' shows a past revision's status."

# ─────────────────────────── 11 ───────────────────────────
Q[11]="The release 'web' in namespace 'demo' must additionally carry CPU and memory
LIMITS of 200m and 256Mi, stored by Helm as a nested 'resources.limits' object
with both values as strings.
Everything the release already has must survive. No values file — do it from
the command line."
PTS[11]=8
SOL[11]="helm upgrade web podinfo/podinfo --version 6.9.0 -n demo --reuse-values \\
  --set-json 'resources={\"limits\":{\"cpu\":\"200m\",\"memory\":\"256Mi\"}}'"
WALK[11]="1. --set-json takes a JSON value and stores it as the structure it is,
   which is how you set a whole subtree in one flag:

     helm upgrade web podinfo/podinfo --version 6.9.0 -n demo \\
       --reuse-values \\
       --set-json 'resources={\"limits\":{\"cpu\":\"200m\",\"memory\":\"256Mi\"}}'

   Note the single quotes around the whole argument — the JSON is full of
   double quotes and braces, and the shell must not touch them.

   --reuse-values covers 'everything it already has must survive'. Without it
   this upgrade silently resets replicaCount and the NodePort service, and
   costs you task 8 as well.

2. Repeated --set reaches the same stored result here, and is worth knowing
   as the fallback:

     --set resources.limits.cpu=200m --set resources.limits.memory=256Mi

   It works in this case because '200m' and '256Mi' are not numbers, so
   Helm's type guessing has nothing to get wrong. --set-json is the tool to
   reach for when the value IS ambiguous — an array, an explicit null, a
   quantity like '3' that must stay a string — because the JSON says the type
   outright instead of leaving it to a parser.

3. Verify the SHAPE, not just the presence of the numbers:

     helm get values web -n demo -o json

   You want '\"resources\":{\"limits\":{\"cpu\":\"200m\",\"memory\":\"256Mi\"}}'
   — an object, with quoted strings. And confirm it reached the pod spec:

     kubectl get deploy web-podinfo -n demo \\
       -o jsonpath='{.spec.template.spec.containers[0].resources}'

The --set family, since exams pick between them deliberately:

     --set          type-guessing: 1.25 becomes a number
     --set-string   always a string — image tags, versions
     --set-json     arbitrary JSON: objects, arrays, explicit null
     --set-file     the value is the CONTENTS of a file (certs, scripts)

Common traps: --set-json arrived in Helm 3.10. On anything older the flag
does not exist and you fall back to repeated --set or a values file. And
forgetting --reuse-values here is the expensive mistake — it does not just
lose this task, it silently undoes task 6 and task 8."

# ─────────────────────────── 12 ───────────────────────────
Q[12]="Download chart podinfo 6.9.0 from the OCI registry
${PODINFO_OCI} and leave it UNPACKED under
${EX3}/dist, so that ${EX3}/dist/podinfo/Chart.yaml exists.
Nothing may be installed, and no .tgz archive may be left behind."
PTS[12]=9
SOL[12]="helm pull ${PODINFO_OCI} --version 6.9.0 \\
  --untar --untardir ${EX3}/dist"
WALK[12]="1. 'helm pull' fetches a chart without touching the cluster. By default it
   drops a .tgz in the current directory:

     helm pull ${PODINFO_OCI} --version 6.9.0
     ls                                  # podinfo-6.9.0.tgz

   The task wants it unpacked and in a specific place, so two more flags:

     --untar                 extract it, and remove the archive afterwards
     --untardir <dir>        where to extract (created if missing)

     helm pull ${PODINFO_OCI} --version 6.9.0 \\
       --untar --untardir ${EX3}/dist

   Note --untardir only applies together with --untar; on its own it is
   silently ignored, which is a good way to lose the points.

2. Verify the layout and the version, and that no archive survived:

     ls ${EX3}/dist/podinfo/          # Chart.yaml templates values.yaml ...
     grep '^version' ${EX3}/dist/podinfo/Chart.yaml    # 6.9.0
     ls ${EX3}/dist/*.tgz             # no such file — correct
     helm list -A                     # unchanged, nothing installed

3. Why this is a real skill and not trivia: an unpacked chart is how you
   inspect or patch a third-party chart before deploying it — read the
   templates, edit values.yaml, then install from the directory:

     helm install local ${EX3}/dist/podinfo -n demo --dry-run

Related: 'helm pull --verify' checks the provenance signature, and
'helm show all <chart>' reads the same content without unpacking anything —
use pull when you need the files on disk, show when you only need to read."

# ─────────────────────────── 13 ───────────────────────────
Q[13]="Write into ${ANS}/q13.txt a complete inventory of the Helm releases in
this cluster: every namespace, and every status — not only the deployed ones."
PTS[13]=7
SOL[13]="helm list -A > ${ANS}/q13.txt        # Helm 4: all statuses by default
# On Helm 3 the same task needs the --all flag:
#   helm list -A -a > ${ANS}/q13.txt"
WALK[13]="1. 'Every namespace' is always a flag; 'every status' depends on your Helm
   version, which is the trap:

     -A / --all-namespaces   both versions — without it you see one namespace
     -a / --all              Helm 3 ONLY. Helm 4 removed it and lists every
                             status by default, so passing it errors out.

   Check what you are on before choosing:

     helm version --short
     helm list -A > ${ANS}/q13.txt        # Helm 4
     helm list -A -a > ${ANS}/q13.txt     # Helm 3

2. Verify the file has the releases you created across three namespaces:

     cat ${ANS}/q13.txt
     # argocd   argocd  ... deployed
     # oci-web  demo    ... deployed
     # web      demo    ... deployed

   'stuck-report' should NOT be there — task 9 removed it. If you see it,
   task 9 is not actually done.

3. For scripting, ask for a machine-readable shape instead of parsing
   columns:

     helm list -A -o json
     helm list -A -o yaml

The status filters are the version-proof way to ask, because they exist in
both Helm 3 and Helm 4:

     helm list -A --failed        # failed only
     helm list -A --pending       # pending-install / pending-upgrade
     helm list -A --uninstalled   # kept with --keep-history
     helm list -A --deployed      # what Helm 3 showed by default
     helm list -A -f '^web'       # regex on the release name
     helm list -A --max 5 --date  # newest first, capped

Common traps: 'helm list' is namespace-scoped like kubectl. Forgetting -A is
the single most common reason a task that says 'find the release' scores
zero — the release is fine, you were just looking in one namespace."

# ─────────────── grading helpers ───────────────
# Helm 3 hides pending/uninstalling releases from 'helm list' unless you pass
# -a/--all. Helm 4 REMOVED that flag, because it now lists every status by
# default — so '-a' is not merely unnecessary there, it is a hard error:
#   Error: unknown shorthand flag: 'a' in -a
# Probe the capability once rather than parsing version numbers.
if helm list -a --max 1 >/dev/null 2>&1; then HALL="-a"; else HALL=""; fi

hfield(){ # release ns field -> value
  helm list -n "$2" $HALL --filter "^$1\$" -o json 2>/dev/null \
    | tr '{},' '\n' | grep "\"$3\":" | head -1 | cut -d'"' -f4
}
hlistall(){ helm list -A $HALL 2>/dev/null; }
hvals(){ helm get values "$1" -n "$2" ${3:-} -o json 2>/dev/null; }
nsexists(){ kubectl get ns "$1" >/dev/null 2>&1; }
filehas(){ [ -f "$1" ] && grep -q "$2" "$1"; }
countin(){ # file pattern -> matching line count, 0 if the file is absent.
  # Note 'grep -c' prints 0 AND exits 1 when there is no match, so an
  # '|| echo 0' fallback would print twice. Assign instead.
  local n=0
  [ -f "$1" ] && n="$(grep -c "$2" "$1" 2>/dev/null)"
  echo "${n:-0}"
}
repoalias(){ helm repo list -o json 2>/dev/null | grep -q "\"name\":\"$1\""; }

check(){
  case "$1" in
    1) repoalias argo \
       && helm repo list -o json 2>/dev/null | grep -q 'argoproj.github.io/argo-helm' \
       && helm search repo argo/argo-cd 2>/dev/null | grep -q 'argo-cd' ;;
    2) filehas "$ANS/q2.yaml" 'kind: Deployment' \
       && filehas "$ANS/q2.yaml" 'argocd-server' \
       && [ "$(countin "$ANS/q2.yaml" 'kind: CustomResourceDefinition')" -eq 0 ] ;;
    3) nsexists argocd \
       && [ "$(hfield argocd argocd status)" = "deployed" ] \
       && [ "$(hfield argocd argocd chart)" = "argo-cd-7.9.1" ] \
       && ! kubectl get crd applications.argoproj.io >/dev/null 2>&1 ;;
    4) repoalias traefik \
       && [ "$(countin "$ANS/q4.yaml" 'kind: CustomResourceDefinition')" -ge 10 ] \
       && ! hlistall | grep -qE '^traefik[[:space:]]' ;;
    5) repoalias ingress-nginx \
       && [ -f "$ANS/q5.txt" ] \
       && [ "$(tr -d '[:space:]"' < "$ANS/q5.txt")" = "1.12.0" ] ;;
    6) nsexists demo \
       && filehas "$EX3/web-values.yaml" 'replicaCount' \
       && filehas "$EX3/web-values.yaml" 'NodePort' \
       && [ "$(hfield web demo status)" = "deployed" ] \
       && hvals web demo | grep -q '"replicaCount":2' \
       && hvals web demo | grep -q '"type":"NodePort"' ;;
    7) [ "$(hfield oci-web demo status)" = "deployed" ] \
       && [ "$(hfield oci-web demo chart)" = "podinfo-6.9.0" ] ;;
    8) [ "$(hfield web demo chart)" = "podinfo-6.9.0" ] \
       && hvals web demo | grep -q '"replicaCount":2' \
       && hvals web demo | grep -q '"type":"NodePort"' ;;
    # nsexists limbo keeps this from passing on an unseeded cluster, where
    # "the stuck release is absent" would otherwise be trivially true. The
    # release-secret check is the real proof: a release Helm still knows about
    # always has one, whatever 'helm list' chooses to show.
    9) nsexists limbo \
       && ! hlistall | grep -q 'stuck-report' \
       && ! kubectl get secret -n limbo -o name 2>/dev/null \
            | grep -q 'sh.helm.release.v1.stuck-report' ;;
    10) filehas "$ANS/q10.txt" 'oci-web-podinfo' \
       && filehas "$ANS/q10.txt" 'Deployment' ;;
    11) hvals web demo | tr -d ' ' | grep -q '"limits"' \
       && hvals web demo | tr -d ' ' | grep -q '"cpu":"200m"' \
       && hvals web demo | tr -d ' ' | grep -q '"memory":"256Mi"' ;;
    12) [ -f "$EX3/dist/podinfo/Chart.yaml" ] \
       && grep -Eq '^version:[[:space:]]*6\.9\.0[[:space:]]*$' "$EX3/dist/podinfo/Chart.yaml" \
       && ! ls "$EX3"/dist/*.tgz >/dev/null 2>&1 ;;
    13) filehas "$ANS/q13.txt" 'argocd' \
       && filehas "$ANS/q13.txt" 'oci-web' \
       && filehas "$ANS/q13.txt" 'web' \
       && ! filehas "$ANS/q13.txt" 'stuck-report' ;;
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
  printf "\n%s┌─ Exam 3 · Task %s/%s ─ %s points%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N"
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
  printf "\n%s  cka-helm-practice · exam 3%s — %s Helm tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sReal public charts and a real OCI registry. Needs internet access.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-20s %s\n" "$CL"           "list every task with its points and status"
  printf "    %-20s %s\n" "$CQ N"         "show task N"
  printf "    %-20s %s\n" "$CG"           "grade everything and print the score"
  printf "    %-20s %s\n" "$CG N"         "grade task N only"
  printf "    %-20s %s\n" "$CE N"         "step-by-step walkthrough, with the reasoning"
  printf "    %-20s %s\n" "$CS N"         "just the commands, no explanation"
  printf "    %-20s %s\n" "$CH"           "this text"
  printf "    %-20s %s\n" "$CL version"   "print the exam suite version"
  printf "    %-20s %s\n\n" "$CL reset"   "re-seed exam 3 from scratch"
  if [ -n "${EXAM_HOME:-}" ]; then
    printf "%s  TAB COMPLETION%s\n\n" "$BO" "$N"
    printf "    q3, grade3, explain3 and solve3 complete task numbers with Tab.\n\n"
  else
    printf "%s  SHORTER COMMANDS%s\n\n" "$BO" "$N"
    printf "    Load the shell functions once and drop the './exam3.sh' prefix:\n\n"
    printf "      source %s/activate.sh\n\n" "$HERE"
    printf "    Then: %sexam3%s, %sq3 4%s, %sgrade3%s, %sexplain3 4%s from any directory.\n\n" \
      "$BO" "$N" "$BO" "$N" "$BO" "$N" "$BO" "$N"
  fi
  printf "%s  WHAT IS DIFFERENT ABOUT EXAM 3%s\n\n" "$BO" "$N"
  printf "    Exams 1 and 2 serve their charts from localhost and work offline.\n"
  printf "    Exam 3 uses the sources the current CKA actually asks about:\n\n"
  printf "      argo           %s\n" "$ARGO_URL"
  printf "      traefik        %s\n" "$TRAEFIK_URL"
  printf "      ingress-nginx  %s\n" "$NGINX_URL"
  printf "      podinfo        %s\n" "$PODINFO_URL"
  printf "      podinfo (OCI)  %s\n\n" "$PODINFO_OCI"
  printf "    No repository is pre-configured: registering them is part of the\n"
  printf "    tasks, as it is in the exam.\n\n"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    1 → 2 → 3     task 1 adds the repo that 2 and 3 render and install\n"
  printf "    6 → 8 → 11    the same release 'web', upgraded twice\n"
  printf "    6 → 7 → 10    task 6 creates namespace 'demo'; 10 reads task 7's release\n"
  printf "    9 before 13   task 13 checks that the stuck release is already gone\n\n"
  printf "%s  HOW IT WORKS%s\n\n" "$BO" "$N"
  printf "    Answers are the cluster's actual state. Tasks that want a file say\n"
  printf "    so; those files live in %s/\n" "$ANS"
  printf "    Values files and charts you author go in %s/\n\n" "$EX3"
  printf "    %sIf the Killercoda session expires, run %s/setup3.sh again.%s\n\n" "$D" "$HERE" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Helm exam 3 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %sreal public charts + OCI registry%s\n\n" "$D" "$N"
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
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps)
    need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 3 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  reset) bash "$HERE/setup3.sh" ;;
  # 'info' exists on every exam so the cka dispatcher has one word for
  # all of them; these three have no dashboard, so it lists the tasks.
  info) exec "$0" list ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s (exam 3)\n" "$VERSION" ;;
  *)
    printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"
    usage; exit 1 ;;
esac
