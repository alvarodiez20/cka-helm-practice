#!/usr/bin/env bash
# ============================================================
#  cka-practice · exam11.sh
#  13 CKA-style Kustomize tasks. 100 points. Pass mark: 66.
#
#    ./exams/exam11.sh q 4 · grade · explain 4 · kustinfo
#
#  The rule that shapes every task here: a transformation must
#  come from the kustomization, not from editing the manifest.
#  So most graders check the applied object AND that the base
#  manifest still says what it always said.
# ============================================================
set -uo pipefail

BASE="${HOME}"; ANS="$BASE/answers11"; EX11="$BASE/exam11"
NS="kust-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

if [ -n "${EXAM_HOME:-}" ]; then
  # activate.sh is loaded: the verbs are unnumbered and act on the exam
  # selected with 'cka use'. See cka.sh.
  CL="list"; CQ="q"; CG="grade"; CE="explain"; CS="solve"; CH="examhelp"
else
  CL="./exams/exam11.sh"; CQ="./exams/exam11.sh q"; CG="./exams/exam11.sh grade"
  CE="./exams/exam11.sh explain"; CS="./exams/exam11.sh solve"; CH="./exams/exam11.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

# ─────────────── task 1 ───────────────
Q[1]="'${EX11}/base' holds two plain manifests — deployment.yaml and service.yaml —
and no kustomization.yaml.
Write '${EX11}/base/kustomization.yaml' so that both are included, and
'kubectl kustomize ${EX11}/base' renders the Deployment and the Service.
Do not apply anything yet."
PTS[1]=7
SOL[1]="cat > ${EX11}/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
EOF

kubectl kustomize ${EX11}/base"
WALK[1]="1. Look at what you have been given:

     ls ${EX11}/base
     # deployment.yaml  service.yaml

   Two ordinary manifests. Nothing about them is Kustomize-specific, and that
   is the point — a base is just YAML you could have applied with 'kubectl
   apply -f'.

2. A kustomization.yaml is itself a Kubernetes object, so it has the two
   fields every object has:

     apiVersion: kustomize.config.k8s.io/v1beta1
     kind: Kustomization

   Both are optional in practice and both are worth writing anyway. Omit them
   and it still builds; include them and your editor validates the file and
   'kubectl kustomize' tells you plainly when you have mistyped a field.

3. 'resources' is the list of things to include. Paths are relative to the
   kustomization.yaml, and each entry can be a file, a directory containing
   its own kustomization.yaml, or a URL:

     resources:
       - deployment.yaml
       - service.yaml

4. Render it. This prints; it does not touch the cluster:

     kubectl kustomize ${EX11}/base

   You should see the Deployment and the Service, separated by '---', exactly
   as they are on disk — a base with no transformers is a concatenation.

THE FILE NAME IS NOT NEGOTIABLE. Kustomize looks for 'kustomization.yaml',
then 'kustomization.yml', then 'Kustomization', in that order, and nothing
else. 'kustomize.yaml' produces:

     unable to find one of 'kustomization.yaml', 'kustomization.yml' or
     'Kustomization' in directory ...

which is the single most common way this goes wrong.

TWO COMMANDS, AND THE DIFFERENCE BETWEEN THEM:

     kubectl kustomize DIR     render to stdout. Reads no cluster, writes
                               nothing. This is 'kustomize build'.
     kubectl apply -k DIR      render, then apply the result.

   '-k' is the '-f' of kustomization directories. Notice there is no
   standalone 'kustomize' binary in play: it has been vendored into kubectl
   since 1.14, and on the exam machine that is all you have."

# ─────────────── task 2 ───────────────
Q[2]="Every object this base renders must land in namespace '${NS}' and have its
name prefixed with 'web-', so the Deployment becomes 'web-shop' and the
Service becomes 'web-shop'.
Set both from the kustomization — do not edit the manifests — then apply the
base to the cluster with a single command."
PTS[2]=8
SOL[2]="cat > ${EX11}/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NS}
namePrefix: web-

resources:
  - deployment.yaml
  - service.yaml
EOF

kubectl apply -k ${EX11}/base
kubectl -n ${NS} get deploy,svc"
WALK[2]="1. Two transformers, both one line:

     namespace: ${NS}      set .metadata.namespace on every rendered object
     namePrefix: web-      prepend to every .metadata.name

   There is a nameSuffix too, and they compose: namePrefix 'web-' plus
   nameSuffix '-v2' gives 'web-shop-v2'.

2. Render before you apply. Always, on the exam and off it:

     kubectl kustomize ${EX11}/base | grep -E 'name:|namespace:'

   'kubectl kustomize' is free and instant, and it is the only way to see
   what '-k' is about to send.

3. Apply it:

     kubectl apply -k ${EX11}/base
     kubectl -n ${NS} get deploy,svc

WHAT namePrefix ALSO DOES, AND WHY IT MATTERS

   It is not a blind string prepend. Kustomize keeps a record of every name
   it rewrites and then fixes up the REFERENCES to those names: a Service
   named in an Ingress backend, a ConfigMap named in a volume, a
   ServiceAccount named in a RoleBinding. That is why you prefix from the
   kustomization instead of with sed.

   What it does NOT rewrite is the label selector. 'app: shop' in
   spec.selector.matchLabels stays 'app: shop', and the pod template's
   'app: shop' stays too, so they still match. Good — see task 3 for the
   transformer that does not leave selectors alone.

4. The namespace field and '-n':

     kubectl apply -k ${EX11}/base -n other

   The kustomization wins. 'namespace:' is baked into the rendered manifests
   before kubectl ever sees them, and an explicit namespace in a manifest
   beats the '-n' flag. If the two disagree kubectl refuses outright.

Common trap: applying with 'kubectl apply -f ${EX11}/base'. That globs the
directory, applies the two raw manifests untransformed into whatever
namespace you are in, and leaves you with an unprefixed 'shop' somewhere
you did not want it. '-k', not '-f'."

# ─────────────── task 3 ───────────────
Q[3]="Every object rendered from the base — the Deployment, the Service, and the
pods the Deployment creates — must carry the label
'app.kubernetes.io/part-of: storefront'.
Add it from the kustomization and re-apply. The Deployment's existing
selector must not change, and base/deployment.yaml must not be edited."
PTS[3]=8
SOL[3]="# add to ${EX11}/base/kustomization.yaml:
#
#   labels:
#     - pairs:
#         app.kubernetes.io/part-of: storefront
#       includeTemplates: true
#
kubectl apply -k ${EX11}/base
kubectl -n ${NS} get deploy web-shop -o jsonpath='{.spec.template.metadata.labels}'"
WALK[3]="1. There are two spellings of this, and choosing the wrong one breaks the
   already-applied Deployment. That is the whole task.

   THE OLD ONE:

     commonLabels:
       app.kubernetes.io/part-of: storefront

   It adds the label to metadata, to the pod template — and to
   spec.selector.matchLabels. On a Deployment that has never been applied
   that is harmless. On this one it is not:

     The Deployment \"web-shop\" is invalid: spec.selector: Invalid value:
     ... field is immutable

   A Deployment's selector cannot be changed after creation. You would have
   to delete and recreate the Deployment to adopt it, which is exactly the
   kind of thing you do not want a label change to require.

   THE CURRENT ONE (kustomize v5, kubectl 1.27+):

     labels:
       - pairs:
           app.kubernetes.io/part-of: storefront
         includeTemplates: true

   'labels' never touches selectors. 'includeTemplates: true' is what carries
   the label into the pod template, so the pods get it too — without it you
   label the Deployment and the Service and nothing that actually runs.

2. Write it, render it, and read the three places it has to appear:

     kubectl kustomize ${EX11}/base | grep -n 'part-of'
     # metadata of the Deployment, metadata of the Service, and the pod template

3. Apply and confirm the selector is untouched:

     kubectl apply -k ${EX11}/base
     kubectl -n ${NS} get deploy web-shop \\
       -o jsonpath='{.spec.selector.matchLabels}{\"\\n\"}{.spec.template.metadata.labels}'

   The selector should still be exactly {\"app\":\"shop\"}.

4. The sibling field, which has no such trap:

     commonAnnotations:
       team: storefront

   Annotations are never selectors, so there is only one spelling of it.

If your kubectl embeds kustomize v4 or older, 'labels' is not recognised and
you have to use commonLabels — in which case delete the Deployment first and
let the apply recreate it. Check with:

     kubectl version --client        # look for 'Kustomize Version'

Why the grader cares that base/deployment.yaml is unchanged: adding the label
by hand to the manifest produces an identical cluster and defeats the entire
purpose of the tool. Kustomize exists so the base stays generic."

# ─────────────── task 4 ───────────────
Q[4]="The rendered Deployment must run image 'nginx:1.27-alpine'.
Change it from the kustomization and re-apply. base/deployment.yaml must
still name the image it names now."
PTS[4]=8
SOL[4]="# add to ${EX11}/base/kustomization.yaml:
#
#   images:
#     - name: nginx
#       newTag: 1.27-alpine
#
kubectl apply -k ${EX11}/base
kubectl -n ${NS} get deploy web-shop -o jsonpath='{.spec.template.spec.containers[0].image}'"
WALK[4]="1. The images transformer matches on the image NAME as written in the
   manifest, and replaces the parts you name:

     images:
       - name: nginx            # what the manifest says, before the ':'
         newTag: 1.27-alpine

   The three fields you can set:

     newTag       change the tag only            nginx:alpine -> nginx:1.27-alpine
     newName      change the repository only     nginx -> registry.local/nginx
     digest       pin by digest instead of tag   nginx@sha256:...

   newName and newTag combine. digest replaces the tag, and setting both
   digest and newTag is an error.

2. Check what 'name' has to match. It is the image string minus the tag, as
   the manifest writes it — not the container name:

     grep image: ${EX11}/base/deployment.yaml
     #   image: nginx:alpine     ->  name: nginx

   'name: web' (the container's name) silently matches nothing. The render
   succeeds, the image is unchanged, and there is no warning. That is the
   trap in this task.

3. Render, then apply:

     kubectl kustomize ${EX11}/base | grep 'image:'
     kubectl apply -k ${EX11}/base

4. Verify against the cluster, not the render:

     kubectl -n ${NS} get deploy web-shop \\
       -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'

WHY THIS IS A TRANSFORMER AND NOT A PATCH

   It is the one field that changes on nearly every promotion between
   environments, so it gets a first-class spelling that does not require you
   to know where in the tree the container sits. A strategic-merge patch to
   do the same thing has to reproduce the name, the kind, and the path down
   to containers[name=web] — four times as much YAML, and it breaks when
   somebody renames the container.

   'kubectl set image' would also work on the live object, and would be
   silently reverted by the next 'apply -k'. The kustomization is the source
   of truth; edit that."

# ─────────────── task 5 ───────────────
Q[5]="The Deployment must run 4 replicas.
Set that from the kustomization and re-apply, leaving base/deployment.yaml at
the replica count it declares now."
PTS[5]=7
SOL[5]="# add to ${EX11}/base/kustomization.yaml:
#
#   replicas:
#     - name: shop
#       count: 4
#
kubectl apply -k ${EX11}/base
kubectl -n ${NS} get deploy web-shop"
WALK[5]="1. The replicas transformer, like images, exists because this is the other
   field that changes per environment:

     replicas:
       - name: shop
         count: 4

2. THE NAME IS THE ORIGINAL NAME, NOT THE PREFIXED ONE.

   The Deployment in the cluster is 'web-shop'. The transformer wants
   'shop' — the name as the resource is written in the base, before
   namePrefix runs. Transformers are matched against the resource's original
   identity; the rename is applied afterwards.

   Write 'name: web-shop' and nothing matches, the render succeeds, and the
   replica count is unchanged. Same failure mode as task 4, same lack of a
   warning. Check by rendering:

     kubectl kustomize ${EX11}/base | grep -A1 'kind: Deployment'
     kubectl kustomize ${EX11}/base | grep 'replicas:'

3. Apply and watch it scale:

     kubectl apply -k ${EX11}/base
     kubectl -n ${NS} get deploy web-shop -w

4. What it can be applied to: anything with a .spec.replicas — Deployment,
   ReplicaSet, ReplicationController, StatefulSet. Not a DaemonSet, which
   has no replica count at all.

A REAL WARNING ABOUT THIS ONE

   If an HPA is managing the same Deployment, a 'replicas' transformer and
   the autoscaler will fight: every 'apply -k' resets the count and the HPA
   moves it back. In that situation you leave replicas out of the
   kustomization entirely and let the HPA own the field. Worth knowing
   because it is a real outage and it looks like a flapping deployment.

Why not just 'kubectl scale'? Same answer as task 4: the next 'apply -k'
reverts it. Anything you want to persist goes in the kustomization."

# ─────────────── task 6 ───────────────
Q[6]="The application needs configuration from a ConfigMap.
Have the kustomization GENERATE a ConfigMap named 'app-settings' with the two
keys LOG_LEVEL=debug and REGION=eu-west-1, and apply it.
Do not write a ConfigMap manifest by hand."
PTS[6]=9
SOL[6]="# add to ${EX11}/base/kustomization.yaml:
#
#   configMapGenerator:
#     - name: app-settings
#       literals:
#         - LOG_LEVEL=debug
#         - REGION=eu-west-1
#
kubectl apply -k ${EX11}/base
kubectl -n ${NS} get cm"
WALK[6]="1. The generator:

     configMapGenerator:
       - name: app-settings
         literals:
           - LOG_LEVEL=debug
           - REGION=eu-west-1

   Sources, in the order you will meet them:

     literals:   - KEY=value            inline
     files:      - config.properties    one key per file, key = the filename
     files:      - app.conf=src/x.conf  same, with the key named explicitly
     envs:       - .env                 a whole KEY=value file, one key each

   'files' and 'envs' are different and the difference bites: 'files' makes
   ONE key whose value is the entire file; 'envs' makes one key per LINE.

2. Apply it and look at the name:

     kubectl apply -k ${EX11}/base
     kubectl -n ${NS} get cm
     # NAME                           DATA   AGE
     # web-app-settings-92gc7dkf6b    2      3s

   Three things happened. namePrefix put 'web-' in front, as it does for
   every generated object too. And kustomize appended a HASH SUFFIX derived
   from the content.

3. THE HASH IS THE FEATURE.

   A ConfigMap mounted into a pod does not restart that pod when it changes.
   Update the ConfigMap in place and the running pods keep the old values
   until something else happens to restart them — the classic 'I changed the
   config and nothing happened'.

   With a generator, changing a literal changes the hash, which changes the
   ConfigMap's NAME, which changes the Deployment that references it — and
   kustomize rewrites that reference for you. A new name in the pod spec is
   a new pod template, so the rollout happens automatically. Config change
   becomes a deploy, which is what you wanted all along.

   The cost is that old ConfigMaps accumulate; 'kubectl apply --prune' or a
   periodic clean-up is the usual answer.

4. Prove the reference rewriting to yourself later, when a Deployment
   actually consumes it:

     kubectl kustomize ${EX11}/base | grep -B2 -A2 'app-settings'

   The name in envFrom/volumes carries the same hash as the ConfigMap.

The grader looks for a ConfigMap in '${NS}' whose name starts 'web-app-settings-'
and ends in a hash, carrying both keys. A hand-written ConfigMap manifest
named exactly 'app-settings' scores zero — correct object, wrong mechanism,
and it is the mechanism the task is about."

# ─────────────── task 7 ───────────────
Q[7]="A second ConfigMap must be generated for a component that reads it by a
fixed name and cannot cope with the name changing.
Generate a ConfigMap that ends up in the cluster named exactly
'web-feature-flags', with the single key CHECKOUT_V2=true, and apply it.
The first ConfigMap must keep its hash suffix."
PTS[7]=7
SOL[7]="# add to ${EX11}/base/kustomization.yaml:
#
#   configMapGenerator:
#     - name: feature-flags
#       options:
#         disableNameSuffixHash: true
#       literals:
#         - CHECKOUT_V2=true
#
kubectl apply -k ${EX11}/base
kubectl -n ${NS} get cm"
WALK[7]="1. The suffix is switched off per generator, with 'options':

     configMapGenerator:
       - name: app-settings          # keeps its hash
         literals:
           - LOG_LEVEL=debug
           - REGION=eu-west-1
       - name: feature-flags         # no hash
         options:
           disableNameSuffixHash: true
         literals:
           - CHECKOUT_V2=true

2. There is also a file-wide switch:

     generatorOptions:
       disableNameSuffixHash: true

   It applies to EVERY generator in the kustomization, so using it here would
   also strip the hash off app-settings and fail the task. That contrast is
   the point: per-generator 'options' when one object needs it, top-level
   'generatorOptions' when they all do.

3. 'web-', not 'feature-flags': namePrefix still applies. Disabling the hash
   turns off the hash, not the rest of the pipeline. The rendered name is
   prefix + name + (suffix), and only the last part went away.

     kubectl apply -k ${EX11}/base
     kubectl -n ${NS} get cm
     # web-app-settings-92gc7dkf6b   2
     # web-feature-flags             1

4. When you actually want this, and when you do not:

     WANT IT     something outside this kustomization refers to the ConfigMap
                 by name — an operator, a chart, a CronJob you did not
                 render here, a controller reading a well-known name.
     DO NOT      anything inside the kustomization consumes it. You have just
                 given up the automatic rollout described in task 6 and gone
                 back to editing a ConfigMap and wondering why nothing
                 restarted.

'generatorOptions' also carries 'labels' and 'annotations', applied to every
generated object — a tidy way to mark generated config as generated."

# ─────────────── task 8 ───────────────
Q[8]="The application also needs a Secret.
Have the kustomization generate an Opaque Secret named 'db-auth' with the key
'password' set to 's3cr3t', and apply it.
Do not write a Secret manifest and do not base64-encode anything by hand."
PTS[8]=7
SOL[8]="# add to ${EX11}/base/kustomization.yaml:
#
#   secretGenerator:
#     - name: db-auth
#       literals:
#         - password=s3cr3t
#
kubectl apply -k ${EX11}/base
kubectl -n ${NS} get secret"
WALK[8]="1. secretGenerator is configMapGenerator with a different output kind:

     secretGenerator:
       - name: db-auth
         literals:
           - password=s3cr3t

   Same sources — literals, files, envs — same hash suffix, same namePrefix,
   same options block.

2. YOU GIVE IT PLAINTEXT. It base64-encodes for you:

     kubectl kustomize ${EX11}/base | grep -A3 'kind: Secret'
     #   password: czNjcjN0

   Pre-encoding is the mistake to avoid. Write 'password=czNjcjN0' and you
   get a Secret whose decoded value is the string 'czNjcjN0', double-encoded
   and wrong, with nothing to warn you.

     echo -n s3cr3t | base64          # czNjcjN0   <- what kustomize produces
     kubectl -n ${NS} get secret web-db-auth-XXXX \\
       -o jsonpath='{.data.password}' | base64 -d

3. The type field, if you need something other than Opaque:

     secretGenerator:
       - name: tls-cert
         type: kubernetes.io/tls
         files:
           - tls.crt=cert.pem
           - tls.key=key.pem

   Opaque is the default and is what this task wants.

4. Apply and check:

     kubectl apply -k ${EX11}/base
     kubectl -n ${NS} get secret
     # web-db-auth-9tbhk4mm7c   Opaque   1

BASE64 IS NOT ENCRYPTION, and a literal in a kustomization.yaml is a
plaintext password in your git history. Real answers are an external secret
store, sealed-secrets, SOPS, or the KMS provider for etcd encryption at rest.
The CKA asks you to create Secrets, so create them — but know that the
generator's convenience is exactly what makes committing one a bad habit."

# ─────────────── task 9 ───────────────
Q[9]="Create a production overlay at '${EX11}/overlays/prod' that builds on the
base, and use it to give the web container resource requests of 100m CPU and
128Mi memory — via a strategic-merge patch in the overlay, not by editing the
base. Apply the overlay.
Rendering the base on its own must still show no resource requests."
PTS[9]=9
SOL[9]="mkdir -p ${EX11}/overlays/prod

cat > ${EX11}/overlays/prod/resources-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
spec:
  template:
    spec:
      containers:
        - name: web
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF

cat > ${EX11}/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  - path: resources-patch.yaml
EOF

kubectl apply -k ${EX11}/overlays/prod"
WALK[9]="1. An overlay is a kustomization whose 'resources' points at another
   kustomization directory:

     resources:
       - ../../base

   That is the whole idea. The base knows nothing about the overlay; the
   overlay inherits everything the base renders, then changes it. You can
   have as many as you like — dev, staging, prod — all pointing at one base.

2. A strategic-merge patch is a PARTIAL manifest. It needs exactly enough to
   identify the object and the field:

     apiVersion: apps/v1        # apiVersion + kind + name identify the target
     kind: Deployment
     metadata:
       name: shop               # again: the ORIGINAL name, not web-shop
     spec:
       template:
         spec:
           containers:
             - name: web        # the list key that selects which container
               resources:
                 requests:
                   cpu: 100m
                   memory: 128Mi

   Everything you do not mention is left alone. That is what makes it
   'strategic' rather than a plain merge: kustomize knows that 'containers'
   is a list keyed by 'name', so it merges into the entry called 'web'
   instead of replacing the whole list.

3. Wire it up:

     patches:
       - path: resources-patch.yaml

   'patches' is the current field and takes both patch styles. You will still
   see 'patchesStrategicMerge' and 'patchesJson6902' in older material — both
   are deprecated in favour of this one list, and both still work.

4. Render both and compare. This is the check the grader makes:

     kubectl kustomize ${EX11}/base            | grep -c resources:   # 0
     kubectl kustomize ${EX11}/overlays/prod   | grep -A4 'resources:'

   The base must stay clean. An overlay that works by editing the base is
   not an overlay.

5. Apply the overlay:

     kubectl apply -k ${EX11}/overlays/prod

   Same object names as before — 'web-shop' — so this updates the Deployment
   in place rather than creating a second one. The overlay inherits
   namespace, namePrefix, labels, images and replicas from the base.

THE DIRECTORY LAYOUT THIS IMPLIES, which is the one you will see everywhere:

     base/
       kustomization.yaml
       deployment.yaml
       service.yaml
     overlays/
       prod/
         kustomization.yaml
         resources-patch.yaml"

# ─────────────── task 10 ───────────────
Q[10]="The production Service must carry the annotation
'monitoring.example.com/scrape: \\\"true\\\"'.
Add it in the prod overlay using a JSON 6902 patch — an inline op/path/value
patch, not a strategic-merge one — and re-apply.
The base on its own must still render the Service without that annotation."
PTS[10]=8
SOL[10]="# add to ${EX11}/overlays/prod/kustomization.yaml:
#
#   patches:
#     - path: resources-patch.yaml
#     - target:
#         kind: Service
#         name: shop
#       patch: |-
#         - op: add
#           path: /metadata/annotations
#           value:
#             monitoring.example.com/scrape: \"true\"
#
kubectl apply -k ${EX11}/overlays/prod
kubectl -n ${NS} get svc web-shop -o jsonpath='{.metadata.annotations}'"
WALK[10]="1. The two patch styles, and when each is the right tool:

     STRATEGIC MERGE   you write what the object should look like, partially.
                       Natural for setting fields and merging into lists that
                       have a merge key.
     JSON 6902         you write OPERATIONS: add, replace, remove, move, copy,
                       test. The only way to express a delete, and the only
                       precise way to address a list POSITION.

   'remove' has no strategic-merge equivalent worth using, which is the usual
   reason to reach for 6902.

2. A 6902 patch needs a target selector, because unlike a merge patch its
   body carries no apiVersion/kind/name to identify anything:

     patches:
       - target:
           kind: Service
           name: shop            # the original name again
         patch: |-
           - op: add
             path: /metadata/annotations
             value:
               monitoring.example.com/scrape: \"true\"

   'target' can also match on group, version, namespace, labelSelector or
   annotationSelector — a labelSelector target patches every object that
   matches, which is how you set one field across a dozen resources.

3. THE PATH IS A JSON POINTER, and it is where these go wrong:

     /metadata/annotations                       the whole map
     /metadata/annotations/monitoring.example.com~1scrape
                                                 one key — '/' is escaped
                                                 as '~1', and '~' as '~0'
     /spec/template/spec/containers/0/image      list index, zero-based
     /spec/ports/-                               '-' means append

   Because the key here contains a slash, adding the whole map in one 'add'
   is far less error-prone than addressing the key. And 'add' on
   /metadata/annotations replaces the map if one already exists, which is
   fine here and is worth knowing when it is not.

4. Quote the value. Annotation values are strings, and 'true' unquoted is a
   YAML boolean:

     value:
       monitoring.example.com/scrape: \"true\"

   Without the quotes you get 'cannot unmarshal bool into Go value of type
   string' from the API server, at apply time, from a render that looked fine.

5. Verify on both sides:

     kubectl kustomize ${EX11}/base          | grep -c 'scrape'   # 0
     kubectl apply -k ${EX11}/overlays/prod
     kubectl -n ${NS} get svc web-shop -o jsonpath='{.metadata.annotations}{\"\\n\"}'

'patch:' inline versus 'path:' to a file — both work for either style. Inline
keeps a three-line patch next to its target; a file is better once it grows."

# ─────────────── task 11 ───────────────
Q[11]="Write everything the prod overlay renders to '${ANS}/q11.yaml', without
applying any of it.
The cluster must not be modified by this task."
PTS[11]=7
SOL[11]="kubectl kustomize ${EX11}/overlays/prod > ${ANS}/q11.yaml
head -20 ${ANS}/q11.yaml"
WALK[11]="1. The command is the one from task 1, redirected:

     kubectl kustomize ${EX11}/overlays/prod > ${ANS}/q11.yaml

   'kubectl kustomize' renders and prints. It opens no connection to the API
   server — you can run it on a laptop with no cluster at all — and it is
   therefore the safe half of 'apply -k'.

2. The equivalent with a dry run, which is NOT the same thing:

     kubectl apply -k ${EX11}/overlays/prod --dry-run=client -o yaml
     kubectl apply -k ${EX11}/overlays/prod --dry-run=server -o yaml

     --dry-run=client   renders and formats it as kubectl would send it.
                        Still no cluster contact for the decision.
     --dry-run=server   sends it to the API server, which validates it,
                        runs admission, and returns what WOULD be stored —
                        then discards it. Catches a rejected field, a quota,
                        a webhook. Needs a cluster and needs permission.

   Server dry-run is the one worth remembering: it is how you find out that
   a manifest is invalid without finding out by applying it.

3. Why you would want the rendered file at all:

     - to diff two overlays:
         diff <(kubectl kustomize overlays/dev) <(kubectl kustomize overlays/prod)
     - to hand plain YAML to something that does not speak kustomize
     - to review what a change actually did before committing it
     - to check a generated Secret's contents without putting it in a cluster

4. And the diff against what is running right now:

     kubectl diff -k ${EX11}/overlays/prod

   Same '-k' flag. It prints what applying would change, which is the check
   to run before every apply on anything you care about.

The grader reads the file and requires it to contain what the overlay
actually renders — the prefixed names, the patched resource requests, the
generated ConfigMaps. Piping the base instead of the overlay is the mistake
it is looking for."

# ─────────────── task 12 ───────────────
Q[12]="'${EX11}/broken' contains a kustomization that does not build.
Fix it until 'kubectl kustomize ${EX11}/broken' succeeds and renders both the
Deployment and the Service, each with its name prefixed 'batch-'.
There is more than one fault, and each one hides the next. Do not apply it."
PTS[12]=8
SOL[12]="cat > ${EX11}/broken/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namePrefix: batch-

resources:
  - deployment.yaml
  - service.yaml
EOF

kubectl kustomize ${EX11}/broken"
WALK[12]="1. Run it and read the error. That is the entire method here, three times:

     kubectl kustomize ${EX11}/broken

   The faults surface in the order kustomize does its work — parse the file,
   check the kind, then resolve what the file points at — which is NOT the
   order they appear in the file. Fix the one you are shown, re-run, repeat.

2. FAULT ONE — a field with the wrong SHAPE:

     error: invalid Kustomization: json: cannot unmarshal array into Go
     struct field Kustomization.namePrefix of type string

   The file says:

     namePrefix:
       - batch-

   namePrefix is a string; that is a list. This one comes first because the
   whole file has to unmarshal before anything else can be looked at — so it
   hides both of the others, and neither the wrong kind nor the missing file
   is mentioned.

   The distinction to carry:

     STRINGS   namePrefix, nameSuffix, namespace
     MAPS      commonLabels, commonAnnotations
     LISTS     resources, patches, images, replicas, configMapGenerator,
               secretGenerator, labels

   The list-valued ones each take a list of MAPS, which is why 'images' and
   'replicas' need a leading dash and 'namePrefix' must not have one.

     namePrefix: batch-

3. FAULT TWO — the kind:

     error: Failed to read kustomization file under ${EX11}/broken:
     kind should be Kustomization or Component

   The file says 'kind: Kustomize'. It is 'Kustomization', with the -ation:
   the object kind, not the tool name. A genuinely common typo, and the error
   names both acceptable values, which is as clear as these get.

4. FAULT THREE — a resource that is not there:

     error: accumulating resources: accumulation err='accumulating resources
     from 'deploy.yaml': evalsymlink failure on '.../deploy.yaml' : lstat
     .../deploy.yaml: no such file or directory'

   The file on disk is 'deployment.yaml'. Read the error to the end — it names
   the path it could not resolve twice. Check what is actually there:

     ls ${EX11}/broken

   This is the failure you will see most often in real life, and it is
   usually a moved file rather than a typo.

5. When it builds, check it did the right thing rather than just exiting 0:

     kubectl kustomize ${EX11}/broken | grep -E 'kind:|name:'
     # kind: Deployment / name: batch-reports
     # kind: Service    / name: batch-reports

WHY THE ORDER IS WORTH NOTICING. You cannot see fault three until fault one
is fixed, so 'I fixed the obvious thing and it still does not work' is the
expected experience, not a sign you fixed the wrong thing. Kustomize reports
one failure per run because each stage needs the previous one to have
succeeded. Fix, re-run, repeat — do not try to spot all three by reading.

A THING WORTH INTERNALISING: none of these three faults reached the cluster.
Kustomize builds locally and fails locally, so a broken kustomization is
always a fast, offline, complete error message — unlike a manifest that
applies cleanly and behaves wrongly. Build before you apply, every time."

# ─────────────── task 13 ───────────────
Q[13]="Count how many Kubernetes objects the prod overlay renders, and write just
that number to '${ANS}/q13.txt'.
Do this last: tasks 9 to 11 change the answer."
PTS[13]=7
SOL[13]="kubectl kustomize ${EX11}/overlays/prod | grep -c '^kind:' > ${ANS}/q13.txt
cat ${ANS}/q13.txt"
WALK[13]="1. Every rendered object has a top-level 'kind:' at column zero, and only
   top-level objects do — a nested kind would be indented. So:

     kubectl kustomize ${EX11}/overlays/prod | grep -c '^kind:'

   The '^' is doing real work. Without it you also count 'kind:' appearing
   inside a patch body or a CRD schema.

2. Cross-check it a different way, because a count you got one way is worth
   confirming with another:

     kubectl kustomize ${EX11}/overlays/prod | grep -c '^---'
     kubectl kustomize ${EX11}/overlays/prod | grep '^kind:' | sort | uniq -c

   The document-separator count can be off by one depending on whether the
   output starts with a separator, which is exactly why the second command —
   which also tells you WHICH kinds — is the better habit.

3. What should be in there by now, if tasks 1 to 10 are done:

     Deployment      1   from the base, patched by the overlay
     Service         1   from the base, annotated by the overlay
     ConfigMap       2   app-settings (hashed) and feature-flags (not)
     Secret          1   db-auth

   Five. If you get a different number, render it and look — a generator you
   defined twice, or an overlay that pulled in the base twice via two paths,
   both show up here and nowhere else.

4. The same question against the cluster, which is not the same question:

     kubectl -n ${NS} get all,cm,secret

   That includes the ReplicaSet and the pods the Deployment created, and the
   'kube-root-ca.crt' ConfigMap every namespace gets for free. Rendered
   objects are what you declared; cluster objects are those plus everything
   the controllers made from them.

The file must contain a bare number and nothing else. The grader renders the
overlay itself and compares — so if you change the overlay after writing the
file, write it again."

# ─────────────── grading helpers ───────────────
jp(){ kubectl "$@" 2>/dev/null; }
nsok(){ kubectl get ns "$NS" >/dev/null 2>&1; }
filetrim(){ [ -f "$1" ] && tr -d '[:space:]' < "$1"; }

# Render a kustomization directory. Empty output means it did not build —
# which is also what happens with no kubectl at all, so every check that uses
# this is closed by construction.
kbuild(){ kubectl kustomize "$1" 2>/dev/null; }

# Read one field off a live object as JSON, through python, so structural
# comparisons are structural. Same helper shape as the other exams.
pyspec(){ # kind name -- python expr on 'd'
  local kind="$1" name="$2" expr="$3"
  jp -n "$NS" get "$kind" "$name" -o json | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
try: sys.exit(0 if eval("("+sys.argv[1]+")") else 1)
except Exception: sys.exit(1)
' "$expr"
}

# The name of the first ConfigMap/Secret in NS matching a prefix.
generated_name(){ # <kind> <prefix>
  jp -n "$NS" get "$1" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep "^$2" | head -1
}

# A generated name ends in a content hash: exactly the alphabet kustomize
# uses, and always the same length.
has_hash(){ printf '%s' "$1" | grep -qE -- '-[bcdfghkmnpqrtvwxz2456789]{10}$'; }

check(){
  case "$1" in
    # ── 1: the base renders both objects ──────────────────
    # Graded on the RENDER, not the cluster: task 1 explicitly says not to
    # apply anything yet. An empty render fails, which is what happens with
    # no kubectl, a missing kustomization.yaml, or a broken one.
    1) out="$(kbuild "$EX11/base")"
       [ -n "$out" ] || return 1
       printf '%s' "$out" | grep -q '^kind: Deployment' \
       && printf '%s' "$out" | grep -q '^kind: Service' ;;

    # ── 2: namespace + namePrefix, applied ────────────────
    2) nsok || return 1
       [ "$(jp -n "$NS" get deploy web-shop -o jsonpath='{.metadata.name}')" = "web-shop" ] \
       && [ "$(jp -n "$NS" get svc web-shop -o jsonpath='{.metadata.name}')" = "web-shop" ] ;;

    # ── 3: labels transformer, selector untouched ─────────
    # Three positive requirements — the label on the Deployment, on the
    # Service, and in the pod template — plus proof the selector still says
    # what it said and the base manifest was not hand-edited.
    3) nsok || return 1
       key='app\.kubernetes\.io/part-of'
       [ "$(jp -n "$NS" get deploy web-shop -o jsonpath="{.metadata.labels.$key}")" = "storefront" ] \
       && [ "$(jp -n "$NS" get svc web-shop -o jsonpath="{.metadata.labels.$key}")" = "storefront" ] \
       && [ "$(jp -n "$NS" get deploy web-shop -o jsonpath="{.spec.template.metadata.labels.$key}")" = "storefront" ] \
       && pyspec deploy web-shop '
d["spec"]["selector"]["matchLabels"]=={"app":"shop"}' \
       && [ -f "$EX11/base/deployment.yaml" ] \
       && ! grep -q 'part-of' "$EX11/base/deployment.yaml" ;;

    # ── 4: images transformer, base unchanged ─────────────
    4) nsok || return 1
       [ "$(jp -n "$NS" get deploy web-shop -o jsonpath='{.spec.template.spec.containers[0].image}')" \
          = "nginx:1.27-alpine" ] \
       && [ -f "$EX11/base/deployment.yaml" ] \
       && ! grep -q '1\.27-alpine' "$EX11/base/deployment.yaml" ;;

    # ── 5: replicas transformer, base unchanged ───────────
    5) nsok || return 1
       [ "$(jp -n "$NS" get deploy web-shop -o jsonpath='{.spec.replicas}')" = "4" ] \
       && [ -f "$EX11/base/deployment.yaml" ] \
       && [ "$(grep -c 'replicas: 4' "$EX11/base/deployment.yaml")" = "0" ] ;;

    # ── 6: generated ConfigMap, hash suffix intact ────────
    # The hash is the thing being taught, so the hash is what is graded: a
    # hand-written ConfigMap called 'app-settings' has the right data and the
    # wrong name, and scores zero.
    6) nsok || return 1
       cm="$(generated_name configmap web-app-settings-)"
       [ -n "$cm" ] || return 1
       has_hash "$cm" || return 1
       [ "$(jp -n "$NS" get cm "$cm" -o jsonpath='{.data.LOG_LEVEL}')" = "debug" ] \
       && [ "$(jp -n "$NS" get cm "$cm" -o jsonpath='{.data.REGION}')" = "eu-west-1" ] ;;

    # ── 7: the second generator, hash disabled ────────────
    # And the first one must STILL be hashed: the failure mode this task
    # exists to catch is reaching for top-level generatorOptions, which
    # silently strips the suffix off both.
    7) nsok || return 1
       [ "$(jp -n "$NS" get cm web-feature-flags -o jsonpath='{.data.CHECKOUT_V2}')" = "true" ] \
       && cm="$(generated_name configmap web-app-settings-)" \
       && [ -n "$cm" ] && has_hash "$cm" ;;

    # ── 8: generated Secret, encoded once ─────────────────
    8) nsok || return 1
       sec="$(generated_name secret web-db-auth-)"
       [ -n "$sec" ] || return 1
       has_hash "$sec" || return 1
       [ "$(jp -n "$NS" get secret "$sec" -o jsonpath='{.type}')" = "Opaque" ] \
       && [ "$(jp -n "$NS" get secret "$sec" -o jsonpath='{.data.password}')" = "czNjcjN0" ] ;;

    # ── 9: overlay exists, patches, base still clean ──────
    9) nsok || return 1
       over="$(kbuild "$EX11/overlays/prod")"
       [ -n "$over" ] || return 1
       printf '%s' "$over" | grep -q 'name: web-shop' || return 1
       pyspec deploy web-shop '
(lambda r: r.get("cpu")=="100m" and r.get("memory")=="128Mi")(
  (d["spec"]["template"]["spec"]["containers"][0].get("resources") or {}).get("requests") or {})' \
       && base="$(kbuild "$EX11/base")" && [ -n "$base" ] \
       && [ "$(printf '%s' "$base" | grep -c '128Mi')" = "0" ] ;;

    # ── 10: JSON 6902 annotation, overlay only ────────────
    10) nsok || return 1
        [ "$(jp -n "$NS" get svc web-shop \
             -o jsonpath='{.metadata.annotations.monitoring\.example\.com/scrape}')" = "true" ] \
        && base="$(kbuild "$EX11/base")" && [ -n "$base" ] \
        && [ "$(printf '%s' "$base" | grep -c 'monitoring.example.com/scrape')" = "0" ] ;;

    # ── 11: the overlay rendered to a file ────────────────
    # Compared against a fresh render rather than pattern-matched, so piping
    # the base instead of the overlay cannot pass. Whitespace is normalised
    # because a trailing newline from a shell redirect is not a wrong answer.
    11) nsok || return 1
        [ -f "$ANS/q11.yaml" ] || return 1
        over="$(kbuild "$EX11/overlays/prod")"
        [ -n "$over" ] || return 1
        [ "$(printf '%s' "$over" | tr -d '[:space:]')" = "$(filetrim "$ANS/q11.yaml")" ] ;;

    # ── 12: the broken kustomization builds ───────────────
    12) out="$(kbuild "$EX11/broken")"
        [ -n "$out" ] || return 1
        [ "$(printf '%s' "$out" | grep -c '^kind:')" = "2" ] \
        && printf '%s' "$out" | grep -q 'name: batch-reports' \
        && printf '%s' "$out" | grep -q '^kind: Deployment' \
        && printf '%s' "$out" | grep -q '^kind: Service' ;;

    # ── 13: the object count ──────────────────────────────
    13) nsok || return 1
        [ -f "$ANS/q13.txt" ] || return 1
        over="$(kbuild "$EX11/overlays/prod")"
        [ -n "$over" ] || return 1
        n="$(printf '%s\n' "$over" | grep -c '^kind:')"
        [ "${n:-0}" -ge 1 ] && [ "$(filetrim "$ANS/q13.txt")" = "$n" ] ;;

    *) return 2 ;;
  esac
}

kustinfo(){
  printf "\n%s  Kustomize at a glance%s\n\n" "$BO" "$N"

  printf "  %sembedded kustomize%s\n" "$D" "$N"
  kubectl version --client 2>/dev/null | sed -n 's/.*[Kk]ustomize Version/    kustomize/p' \
    || printf "    (unknown)\n"

  printf "\n  %sthe tree%s  %s(%s)%s\n" "$D" "$N" "$D" "$EX11" "$N"
  if [ -d "$EX11" ]; then
    (cd "$EX11" && find . -maxdepth 3 \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null \
      | sed 's|^\./|    |' | sort)
  else
    printf "    (not seeded — run 'reset')\n"
  fi

  printf "\n  %sdoes it build?%s\n" "$D" "$N"
  for dir in base overlays/prod broken; do
    if [ ! -d "$EX11/$dir" ]; then
      printf "    %-14s %s(no such directory)%s\n" "$dir" "$D" "$N"
    elif kubectl kustomize "$EX11/$dir" >/dev/null 2>&1; then
      printf "    %-14s %s✔%s  %s objects\n" "$dir" "$G" "$N" \
        "$(kubectl kustomize "$EX11/$dir" 2>/dev/null | grep -c '^kind:')"
    else
      printf "    %-14s %s✘%s  %s\n" "$dir" "$R" "$N" \
        "$(kubectl kustomize "$EX11/$dir" 2>&1 | head -1 | cut -c1-60)"
    fi
  done

  printf "\n  %sin the cluster (%s)%s\n" "$D" "$NS" "$N"
  out="$(kubectl -n "$NS" get deploy,svc,cm,secret --no-headers 2>/dev/null \
         | grep -v 'kube-root-ca')"
  if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/    /'
  else printf "    (nothing — 'reset' to seed, then apply the base)\n"; fi
  printf "\n"
}

valid_n(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]; }
need_n(){ if ! valid_n "${1:-}"; then printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2; exit 1; fi; }
show(){
  printf "\n%s┌─ Exam 11 · Task %s/%s ─ %s points%s\n%s└%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N" "$B" "$N"
  echo "${Q[$1]}"
  printf "\n%s  when you are done:  %s %s      stuck?  %s %s%s\n\n" "$D" "$CG" "$1" "$CE" "$1" "$N"
}
grade_one(){
  if check "$1"; then printf "  %s✔%s  %2s  %-3s pts   correct\n" "$G" "$N" "$1" "${PTS[$1]}"; return 0
  else printf "  %s✘%s  %2s  %-3s pts   unsolved or incomplete\n" "$R" "$N" "$1" "0"; return 1; fi
}
grade_all(){
  local got=0 max=0 i
  printf "\n%s  Results%s\n\n" "$BO" "$N"
  for i in $(seq 1 $TOTAL); do max=$(( max + ${PTS[$i]} )); if grade_one "$i"; then got=$(( got + ${PTS[$i]} )); fi; done
  local pct=$(( got * 100 / max ))
  printf "\n  %sSCORE: %s/%s  (%s%%)%s   " "$BO" "$got" "$max" "$pct" "$N"
  if [ "$pct" -ge 66 ]; then printf "%sPASS%s\n\n" "$G$BO" "$N"; else printf "%sFAIL%s %s(the CKA pass mark is 66)%s\n\n" "$R$BO" "$N" "$D" "$N"; fi
}
usage(){
  printf "\n%s  cka-practice · exam 11%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sKustomize. Named in the curriculum under Cluster Architecture — 25%%.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-16s %s\n" "$CL" "list every task with its points and status"
  printf "    %-16s %s\n" "$CQ N" "show task N"
  printf "    %-16s %s\n" "$CG" "grade everything"
  printf "    %-16s %s\n" "$CE N" "walkthrough"
  printf "    %-16s %s\n" "$CS N" "just the commands"
  printf "    %-16s %s\n" "kustinfo" "the tree, whether each directory builds, and what is applied"
  printf "    %-16s %s\n\n" "$CH" "this text"
  printf "%s  THE RULE THAT MAKES THIS AN EXAM%s\n\n" "$BO" "$N"
  printf "    Every transformation is graded on the applied or rendered result AND\n"
  printf "    on the base manifests being untouched. Editing base/deployment.yaml to\n"
  printf "    change the image or the replica count produces an identical cluster and\n"
  printf "    scores zero — Kustomize exists so that the base stays generic.\n\n"
  printf "%s  THERE IS NO 'kustomize' BINARY%s\n\n" "$BO" "$N"
  printf "    It is vendored into kubectl. Two commands do everything here:\n\n"
  printf "      kubectl kustomize DIR      render to stdout, touch nothing\n"
  printf "      kubectl apply -k DIR       render, then apply\n\n"
  printf "    And one more worth the muscle memory:  kubectl diff -k DIR\n\n"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    1 before 2       you cannot apply a kustomization you have not written\n"
  printf "    2 before 3-8     those are graded on the applied result\n"
  printf "    9 before 10, 11  the overlay has to exist before you can patch it\n"
  printf "    13 last          it counts what the overlay renders, which 9-11 change\n\n"
  printf "    %sFull layout: %s/README.txt%s\n\n" "$D" "$EX11" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 11 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %sKustomize · namespace: %s · tree: %s%s\n\n" "$D" "$NS" "$EX11" "$N"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   kustinfo   ·   %s%s\n\n" "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show) need_n "${2:-}" "$CQ"; show "$2" ;;
  grade) if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"; else grade_all; fi ;;
  solve) need_n "${2:-}" "$CS"
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps) need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 11 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  kustinfo|info) kustinfo ;;
  reset) bash "$HERE/setup11.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-practice %s (exam 11)\n" "$VERSION" ;;
  *) printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"; usage; exit 1 ;;
esac
