#!/usr/bin/env bash
# ============================================================
#  cka-practice · exam10.sh
#  13 CKA-style tasks on Ingress, the Gateway API, and the CNI.
#  100 points. Pass mark: 66.
#
#    ./exams/exam10.sh q 4 · grade · explain 4 · edgeinfo
#
#  NO controller is installed anywhere in this exam, and that
#  is deliberate. The CKA asks you to WRITE these objects; it
#  does not stand up ingress-nginx for you. Every routing task
#  here is graded on the object, exactly as the real exam
#  grades it. An Ingress with no ADDRESS and a Gateway that is
#  never Programmed are the expected states.
# ============================================================
set -uo pipefail

BASE="${HOME}"; ANS="$BASE/answers10"; EX10="$BASE/exam10"
NS="edge-lab"
NODE="${CKA_NODE:-node01}"
CNIDIR="/etc/cni/net.d"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

if [ -n "${EXAM_HOME:-}" ]; then
  CL="list"; CQ="q"; CG="grade"; CE="explain"; CS="solve"; CH="examhelp"
else
  CL="./exams/exam10.sh"; CQ="./exams/exam10.sh q"; CG="./exams/exam10.sh grade"
  CE="./exams/exam10.sh explain"; CS="./exams/exam10.sh solve"; CH="./exams/exam10.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

# ═══════════════ PART ONE · INGRESS ═══════════════

Q[1]="Create an IngressClass called 'nginx-ext' whose controller is
'k8s.io/ingress-nginx', and make it the default class for the cluster, so an
Ingress that names no class at all is handled by it."
PTS[1]=6
SOL[1]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx-ext
  annotations:
    ingressclass.kubernetes.io/is-default-class: \"true\"
spec:
  controller: k8s.io/ingress-nginx
EOF"
WALK[1]="1. An IngressClass is the join between an Ingress and the controller that
   is supposed to act on it. It is cluster-scoped, like a StorageClass, and
   for the same reason: the cluster operator owns it, not the app team.

     apiVersion: networking.k8s.io/v1
     kind: IngressClass
     metadata:
       name: nginx-ext
       annotations:
         ingressclass.kubernetes.io/is-default-class: \"true\"
     spec:
       controller: k8s.io/ingress-nginx

2. The two fields that matter, and they are easy to confuse:

     metadata.name     what an Ingress puts in spec.ingressClassName
     spec.controller   an opaque string the CONTROLLER matches on itself

   You do not invent spec.controller. It is published by whichever
   implementation you run — 'k8s.io/ingress-nginx' for ingress-nginx,
   'traefik.io/ingress-controller' for Traefik. Get it wrong and every
   Ingress in the class is ignored in silence.

3. The default-class annotation is the only way to make an Ingress with no
   ingressClassName work. Note the quotes: it is the STRING \"true\", and an
   unquoted true in YAML is a boolean, which will be rejected.

   Only one class may be the default. If two claim it, admission rejects new
   Ingresses that omit the class.

4. Verify:

     kubectl get ingressclass
     # NAME        CONTROLLER             PARAMETERS   AGE
     # nginx-ext   k8s.io/ingress-nginx   <none>       5s

     kubectl get ingressclass nginx-ext -o jsonpath='{.metadata.annotations}'

There is no ingress-nginx installed here, so nothing will consume the class.
That is fine — the object is what is graded, and on the CKA it is what is
graded too."

Q[2]="Create an Ingress called 'shop' in namespace '${NS}' that belongs to the
'nginx-ext' class and, for the host 'shop.example.com', routes:

  /       (prefix)  to service 'shop-v1' on port 80
  /api    (prefix)  to service 'api'     on the port that service publishes

Check what port 'api' actually publishes before you write it."
PTS[2]=9
SOL[2]="kubectl -n ${NS} get svc api          # 8080 -> 80
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: ${NS}
spec:
  ingressClassName: nginx-ext
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: shop-v1
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 8080
EOF"
WALK[2]="1. Look before you write. This is the single most common Ingress mistake:

     kubectl -n ${NS} get svc
     # api       ClusterIP   10.x.x.x   <none>   8080/TCP

   The backend port is the SERVICE port, not the container port. 'api'
   listens on 80 inside the pod but publishes 8080, so the Ingress must say
   8080. Naming the container port produces an Ingress that looks perfect and
   returns 503.

2. Generate a skeleton rather than typing YAML from memory — imperative
   creation exists for Ingress and is much faster under time pressure:

     kubectl -n ${NS} create ingress shop --class=nginx-ext \\
       --rule='shop.example.com/*=shop-v1:80' \\
       --rule='shop.example.com/api*=api:8080' --dry-run=client -o yaml

   The trailing '*' in the rule is what makes 'kubectl create ingress' emit
   pathType: Prefix. Without it you get Exact, which is almost never what
   you want.

3. The three pathTypes, because the CKA does ask:

     Prefix            /api matches /api, /api/, /api/orders
                       Matched by PATH ELEMENT, so /apiary does NOT match.
     Exact             /api matches /api and nothing else
     ImplementationSpecific   whatever the controller decides — avoid

   pathType is REQUIRED in networking.k8s.io/v1. There is no default.

4. Ordering between rules is not defined by the Ingress spec — controllers
   conventionally take the longest match, which is why /api wins over / here.
   Do not rely on the order you wrote them in.

5. Verify:

     kubectl -n ${NS} describe ingress shop
     kubectl -n ${NS} get ingress shop \\
       -o jsonpath='{range .spec.rules[*].http.paths[*]}{.path} {.pathType} {.backend.service.name}:{.backend.service.port.number}{\"\\n\"}{end}'

The ADDRESS column stays empty because no controller is running. That is not
a fault and there is nothing to fix."

Q[3]="The Ingress 'legacy' in '${NS}' was written for an old cluster and routes
nothing. Fix it, without changing its host, so that:

  - it belongs to the 'nginx-ext' class the way current Kubernetes expects,
    and the obsolete way of saying so is gone
  - '/api' and everything beneath it reaches the 'api' service
  - the backend port is one the 'api' service actually publishes"
PTS[3]=8
SOL[3]="kubectl -n ${NS} annotate ingress legacy kubernetes.io/ingress.class-
kubectl -n ${NS} patch ingress legacy --type=json -p='[
  {\"op\":\"add\",\"path\":\"/spec/ingressClassName\",\"value\":\"nginx-ext\"},
  {\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths/0/pathType\",\"value\":\"Prefix\"},
  {\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths/0/backend/service/port/number\",\"value\":8080}
]'"
WALK[3]="1. Read it first, and count the faults:

     kubectl -n ${NS} get ingress legacy -o yaml

   There are three, and each is a separate real-world habit:

     annotations:
       kubernetes.io/ingress.class: nginx-ext     <- fault 1
     ...
           - path: /api
             pathType: Exact                       <- fault 2
             backend:
               service:
                 name: api
                 port:
                   number: 80                      <- fault 3

2. Fault 1 — the annotation. Before Kubernetes 1.18 this annotation was how
   you selected a controller. It was deprecated in 1.18 and removed from the
   API's understanding entirely; some controllers still honour it, most do
   not, and the two mechanisms can disagree. spec.ingressClassName is the
   field now. Delete the annotation with a trailing dash:

     kubectl -n ${NS} annotate ingress legacy kubernetes.io/ingress.class-

3. Fault 2 — pathType Exact matches '/api' and nothing else, so /api/orders
   404s. Prefix matches the whole subtree.

4. Fault 3 — port 80 is the container port. 'api' publishes 8080. This is the
   fault that yields a 503 rather than a 404, and it is the one you find by
   comparing the Ingress against 'kubectl get svc' rather than by reading the
   Ingress alone.

5. Edit however you prefer — 'kubectl edit ingress legacy' is perfectly good
   under exam time pressure. Then verify all three at once:

     kubectl -n ${NS} get ingress legacy -o jsonpath='{.spec.ingressClassName}{\"\\n\"}'
     kubectl -n ${NS} get ingress legacy -o jsonpath='{.metadata.annotations}{\"\\n\"}'
     kubectl -n ${NS} describe ingress legacy

The lesson: an Ingress that routes nothing usually has a working controller
and a wrong reference. Check the class, then the service name, then the port,
in that order — it is almost always one of those three."

Q[4]="Serve 'shop.example.com' over TLS.

Create a TLS Secret named 'shop-tls' in '${NS}' from the certificate and key
already on disk at:

  ${EX10}/shop.crt
  ${EX10}/shop.key

and make the Ingress 'shop' present that certificate for shop.example.com."
PTS[4]=8
SOL[4]="kubectl -n ${NS} create secret tls shop-tls \\
  --cert=${EX10}/shop.crt --key=${EX10}/shop.key

kubectl -n ${NS} patch ingress shop --type=json -p='[
  {\"op\":\"add\",\"path\":\"/spec/tls\",\"value\":[{\"hosts\":[\"shop.example.com\"],\"secretName\":\"shop-tls\"}]}
]'"
WALK[4]="1. 'create secret tls' is a dedicated subcommand — do not build the Secret
   by hand and do not base64 anything yourself:

     kubectl -n ${NS} create secret tls shop-tls \\
       --cert=${EX10}/shop.crt --key=${EX10}/shop.key

   It produces type 'kubernetes.io/tls' with exactly two keys, 'tls.crt' and
   'tls.key'. The type is not cosmetic: the API validates that both keys are
   present, and ingress controllers look the Secret up BY type. A generic
   Secret holding the same bytes will not be used.

2. Reference it from the Ingress. The tls block is a sibling of rules, not
   part of one:

     spec:
       tls:
         - hosts:
             - shop.example.com
           secretName: shop-tls
       rules:
         - host: shop.example.com
           ...

3. The rule people get wrong: the host in the tls block must match the host
   in the rule. TLS is terminated by SNI, so the controller picks the
   certificate from the name the client asked for, before it ever looks at
   the path. A tls entry for a host you do not route is dead weight; a rule
   whose host is absent from tls is served plaintext, or with the
   controller's default self-signed certificate.

4. The Secret must live in the SAME namespace as the Ingress. There is no
   cross-namespace reference for Ingress TLS at all — this is one of the
   holes the Gateway API fills, with ReferenceGrant.

5. Verify:

     kubectl -n ${NS} get secret shop-tls
     # TYPE                DATA
     # kubernetes.io/tls   2

     kubectl -n ${NS} get ingress shop -o jsonpath='{.spec.tls}{\"\\n\"}'

If you need a certificate in the exam and none is provided, openssl is there:

     openssl req -x509 -nodes -newkey rsa:2048 -days 365 \\
       -keyout tls.key -out tls.crt -subj \"/CN=shop.example.com\""

Q[5]="Requests routed to the 'orders' service in '${NS}' would return 503 even
though the deployment behind it is running and healthy.

Find out why and fix it, changing only the object that is actually wrong.
Do not relabel the pods and do not recreate the Deployment."
PTS[5]=8
SOL[5]="kubectl -n ${NS} get endpointslice -l kubernetes.io/service-name=orders
kubectl -n ${NS} get pods --show-labels | grep orders
kubectl -n ${NS} patch svc orders -p '{\"spec\":{\"selector\":{\"app\":\"orders\"}}}'"
WALK[5]="1. A 503 from an ingress controller means it had nowhere to send the
   request. Nine times in ten that is a Service with no endpoints, and the
   Ingress is innocent. Check the endpoints FIRST, always:

     kubectl -n ${NS} get endpointslice -l kubernetes.io/service-name=orders
     # NAME           ADDRESSTYPE   PORTS   ENDPOINTS
     # orders-abcde   IPv4          80      <unset>

   No addresses. The Service is selecting nothing.

2. Compare the selector against the labels that exist:

     kubectl -n ${NS} get svc orders -o jsonpath='{.spec.selector}{\"\\n\"}'
     # {\"app\":\"order\"}

     kubectl -n ${NS} get pods --show-labels | grep orders
     # orders-xxxx   1/1   Running   app=orders,pod-template-hash=...

   'order' versus 'orders'. A Service selector is not validated against
   anything — no pod has to match, and nothing warns you. That is by design,
   because a Service may legitimately exist before its workload.

3. Fix the Service, which is the object that is wrong:

     kubectl -n ${NS} patch svc orders -p '{\"spec\":{\"selector\":{\"app\":\"orders\"}}}'

   Note that patching .spec.selector this way REPLACES the whole map, which
   is what you want here.

4. Confirm the endpoints appear — this is immediate, the endpoints
   controller reacts to the Service update:

     kubectl -n ${NS} get endpointslice -l kubernetes.io/service-name=orders
     kubectl -n ${NS} describe svc orders | grep -i endpoints

5. The wider debugging ladder, worth having in muscle memory, because it
   works for Ingress, Gateway and plain Services alike:

     endpoints empty?   -> selector, or pods not Ready
     endpoints present, still 503?  -> wrong port on the Service or the route
     404 instead of 503 -> the host or path did not match at all
     no ADDRESS on the Ingress -> no controller, or the wrong class

Readiness matters too: a pod that is Running but not Ready is deliberately
excluded from the endpoints. So 'no endpoints' can also mean 'your readiness
probe is failing', which is a very different fix."

# ═══════════════ PART TWO · GATEWAY API ═══════════════

Q[6]="Set up the Gateway API side of the same cluster.

  a) Create a GatewayClass called 'edge-class' whose controllerName is
     'example.net/gateway-controller'.
  b) Create a Gateway called 'edge' in namespace '${NS}' that uses it, with a
     single listener named 'http' on port 80, protocol HTTP, which accepts
     routes from its own namespace only.

The Gateway will never become Programmed — no controller implements that
class here. That is expected."
PTS[6]=8
SOL[6]="kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: edge-class
spec:
  controllerName: example.net/gateway-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge
  namespace: ${NS}
spec:
  gatewayClassName: edge-class
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Same
EOF"
WALK[6]="1. The Gateway API replaces Ingress with three objects instead of one,
   split along the lines of who actually owns each decision:

     GatewayClass   the infrastructure team. Which implementation.
                    Cluster-scoped, like IngressClass.
     Gateway        the cluster operator. Which ports, which protocols,
                    which certificates, who may attach.
     HTTPRoute      the application team. Which hostnames and paths go to
                    which of MY services.

   That split is the whole point. Under Ingress, an app team that needed a
   new hostname had to be given edit rights on an object that also controls
   TLS and the load balancer.

2. The GatewayClass:

     spec:
       controllerName: example.net/gateway-controller

   Same idea as IngressClass.spec.controller — an opaque string the
   implementation matches on. It is IMMUTABLE once created; to change it,
   delete and recreate.

3. The Gateway, and the listener fields that carry weight:

     listeners:
       - name: http            required, and referenced by sectionName later
         port: 80
         protocol: HTTP        HTTP | HTTPS | TLS | TCP | UDP
         allowedRoutes:
           namespaces:
             from: Same        Same | All | Selector

   allowedRoutes is the security boundary that Ingress never had. 'Same'
   means only routes in ${NS} may attach. 'Selector' takes a label selector
   over namespaces. Attachment is a HANDSHAKE: the route names the Gateway,
   and the Gateway must permit the route. Either side can refuse.

4. Check what you built:

     kubectl get gatewayclass
     kubectl -n ${NS} get gateway edge
     # NAME   CLASS        ADDRESS   PROGRAMMED   AGE
     # edge   edge-class             Unknown      5s

   PROGRAMMED stays Unknown for ever here, because nothing implements
   'example.net/gateway-controller'. With a real implementation you would
   watch for Accepted=True and Programmed=True, and 'kubectl describe gateway
   edge' is where the reason for a refusal appears.

5. If the CRDs are missing entirely, the API will not know these kinds:

     kubectl get crd | grep gateway.networking.k8s.io
     kubectl apply --server-side -f \\
       https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

   The Gateway API is NOT built into Kubernetes. It ships as CRDs, on its own
   release schedule, in two channels: standard (GA and beta — GatewayClass,
   Gateway, HTTPRoute, GRPCRoute, ReferenceGrant) and experimental."

Q[7]="Create an HTTPRoute called 'shop-route' in '${NS}' that attaches to the
Gateway 'edge', serves the hostname 'shop.example.com', and sends everything
under '/' to the service 'shop-v1' on port 80."
PTS[7]=9
SOL[7]="kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-route
  namespace: ${NS}
spec:
  parentRefs:
    - name: edge
  hostnames:
    - \"shop.example.com\"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: shop-v1
          port: 80
EOF"
WALK[7]="1. The shape of an HTTPRoute, and the one field that decides whether it
   does anything at all:

     spec:
       parentRefs:                  <- WITHOUT THIS THE ROUTE IS INERT
         - name: edge
       hostnames:
         - \"shop.example.com\"
       rules:
         - matches:
             - path:
                 type: PathPrefix
                 value: /
           backendRefs:
             - name: shop-v1
               port: 80

2. parentRefs is the trap, and it is the most commonly reported Gateway API
   exam mistake. An HTTPRoute with no parentRefs — or with a parent that does
   not exist — is accepted by the API without a murmur. kubectl prints no
   error. Nothing warns you. The route simply never attaches and traffic
   never reaches it. The only place it shows is the status:

     kubectl -n ${NS} describe httproute shop-route
     # look at status.parents — a correctly attached route has a parent
     # entry with Accepted=True and ResolvedRefs=True

   Get into the habit of reading status.parents for every route you write.

3. parentRefs may also name a specific listener, which is how you attach to
   the HTTPS listener of a Gateway that has several:

     parentRefs:
       - name: edge
         sectionName: http

   Omit sectionName and the route attaches to every listener that permits it.

4. Path match types, which mirror Ingress but are spelled differently —
   PathPrefix, not Prefix:

     PathPrefix          / matches everything beneath, by path element
     Exact               exactly that path
     RegularExpression   implementation-specific, not in the core set

   And matches can go far beyond path, which Ingress could not do at all:
   headers, query parameters and method are all first-class.

5. backendRefs takes a port and, unlike Ingress, defaults kind to Service and
   namespace to the route's own. Sending traffic to a Service in ANOTHER
   namespace is allowed, but needs a ReferenceGrant in the target namespace
   permitting it — a deliberate, explicit consent object, again something
   Ingress had no answer for.

     kubectl -n ${NS} get httproute shop-route -o yaml"

Q[8]="Canary the shop.

Create an HTTPRoute called 'canary' in '${NS}', attached to the Gateway
'edge', for the hostname 'canary.example.com', which sends 90% of requests to
'shop-v1' and 10% to 'shop-v2' — both on port 80, and both from a single
rule."
PTS[8]=8
SOL[8]="kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary
  namespace: ${NS}
spec:
  parentRefs:
    - name: edge
  hostnames:
    - \"canary.example.com\"
  rules:
    - backendRefs:
        - name: shop-v1
          port: 80
          weight: 90
        - name: shop-v2
          port: 80
          weight: 10
EOF"
WALK[8]="1. Weighted traffic splitting is the headline feature the Gateway API has
   and Ingress does not. Two backendRefs, in ONE rule, each with a weight:

     rules:
       - backendRefs:
           - {name: shop-v1, port: 80, weight: 90}
           - {name: shop-v2, port: 80, weight: 10}

2. Why one rule and not two. Rules are alternatives — the request matches
   one of them and is done. Weights only distribute among the backends of
   the SAME rule. Two rules with the same match and different backends is
   not a split; the first match wins and the second is dead.

3. Weights are RELATIVE, not percentages. 90/10 and 9/1 behave identically,
   and 3/1 is 75%/25%. The share is weight divided by the sum of weights in
   the rule. Writing 90 and 10 makes the intent readable, which is why
   everyone does it, but nothing requires them to total 100.

   A weight of 0 means that backend receives no traffic — which is how you
   drain a version without deleting it. Omitting weight entirely defaults to
   1, so two unweighted backends split 50/50.

4. Note there is no 'matches' block here. Omit matches and the rule matches
   everything for the listed hostnames, which is what a whole-service canary
   wants. You could equally canary just one path by adding a matches block.

5. This is how progressive delivery is done without a service mesh: change
   the numbers, watch your metrics, change them again.

     kubectl -n ${NS} patch httproute canary --type=json \\
       -p='[{\"op\":\"replace\",\"path\":\"/spec/rules/0/backendRefs/1/weight\",\"value\":50}]'

6. Verify:

     kubectl -n ${NS} get httproute canary \\
       -o jsonpath='{range .spec.rules[0].backendRefs[*]}{.name}={.weight} {end}{\"\\n\"}'"

Q[9]="The HTTPRoute 'stale-route' in '${NS}' was left behind by a migration. It is
accepted by the API, kubectl reports no problem with it, and it routes
nothing.

Make it work, keeping its hostname 'orders.example.com', its '/orders' path
and its 'orders' backend exactly as they are."
PTS[9]=7
SOL[9]="kubectl -n ${NS} patch httproute stale-route --type=json \\
  -p='[{\"op\":\"replace\",\"path\":\"/spec/parentRefs/0/name\",\"value\":\"edge\"}]'"
WALK[9]="1. Look at what it is parented to:

     kubectl -n ${NS} get httproute stale-route -o jsonpath='{.spec.parentRefs}{\"\\n\"}'
     # [{\"group\":\"gateway.networking.k8s.io\",\"kind\":\"Gateway\",\"name\":\"old-edge\"}]

     kubectl -n ${NS} get gateway
     # NAME   CLASS        PROGRAMMED
     # edge   edge-class   Unknown

   There is no Gateway called 'old-edge'. The route points at a parent that
   was deleted, or renamed, or never existed.

2. This is the failure mode worth internalising, because nothing surfaces it
   the way you expect. The API server validates the SHAPE of parentRefs, not
   whether the target exists — a dangling reference is a perfectly valid
   object. 'kubectl get httproute' prints no warning. 'kubectl apply' exits
   0. Everything looks healthy and no traffic flows.

   The status is the only place it appears:

     kubectl -n ${NS} describe httproute stale-route

   With a real controller, a route attached to a Gateway that does not exist
   gets no entry in status.parents at all, or one whose Accepted condition
   reads NoMatchingParent. An orphaned route is silent; a rejected one at
   least tells you why.

3. Fix the reference:

     kubectl -n ${NS} patch httproute stale-route --type=json \\
       -p='[{\"op\":\"replace\",\"path\":\"/spec/parentRefs/0/name\",\"value\":\"edge\"}]'

   or 'kubectl -n ${NS} edit httproute stale-route' and change the one word.

4. The other three ways a route can be silently orphaned, all worth checking
   in this order when a route does nothing:

     - parentRefs names a Gateway that does not exist          (this task)
     - the Gateway's allowedRoutes.namespaces refuses your namespace
     - sectionName names a listener the Gateway does not have
     - the route's hostname does not intersect the listener's hostname

   Every one of them produces a route that is valid, accepted by kubectl, and
   completely inert.

5. Verify the reference now resolves:

     kubectl -n ${NS} get httproute stale-route \\
       -o jsonpath='{.spec.parentRefs[0].name}{\"\\n\"}'
     kubectl -n ${NS} get gateway edge"

# ═══════════════ PART THREE · THE CNI ═══════════════

Q[10]="Node '${NODE}' has gone NotReady and no new pod can start on it. Existing
pods are unaffected.

Write into ${ANS}/q10.txt the reason the node itself gives for this — the
phrase in its Ready condition that names what is missing. One line is enough;
copying the whole condition message is fine.

DO THIS BEFORE TASK 11. Repairing the node erases the evidence."
PTS[10]=7
SOL[10]="kubectl describe node ${NODE} | grep -A3 'Ready '
kubectl get node ${NODE} \\
  -o jsonpath='{range .status.conditions[?(@.type==\"Ready\")]}{.message}{\"\\n\"}{end}' \\
  > ${ANS}/q10.txt
cat ${ANS}/q10.txt"
WALK[10]="1. Ask the node, not the logs, first. The kubelet publishes exactly why it
   considers itself unready:

     kubectl describe node ${NODE}
     # Ready   False   KubeletNotReady   container runtime network not ready:
     #   NetworkReady=false reason:NetworkPluginNotReady
     #   message:Network plugin returns error: cni plugin not initialized

   Or as a one-liner you can redirect:

     kubectl get node ${NODE} -o jsonpath='{range .status.conditions[?(@.type==\"Ready\")]}{.message}{\"\\n\"}{end}' \\
       > ${ANS}/q10.txt

2. Read what it is actually saying. 'cni plugin not initialized' is not the
   kubelet complaining about itself — it is the CONTAINER RUNTIME reporting
   upward. Since dockershim was removed in 1.24, the kubelet does not read
   /etc/cni/net.d at all. containerd does, and reports network readiness to
   the kubelet over the CRI. So a CNI fault reaches you through three layers:

     /etc/cni/net.d  ->  containerd  ->  CRI status  ->  kubelet  ->  node

   That is why 'systemctl restart kubelet' does not fix it and
   'systemctl restart containerd' often does.

3. Corroborate from the node, which is where the real detail is:

     ssh ${NODE}
     journalctl -u kubelet -n 40 --no-pager | grep -i cni
     journalctl -u containerd -n 40 --no-pager | grep -i cni
     ls -l ${CNIDIR}

4. Distinguish this from the failures that look like it:

     'cni plugin not initialized'      no usable config in ${CNIDIR}
     'failed to find plugin X in path' config is fine, the BINARY is missing
                                       from /opt/cni/bin
     node Ready, pods stuck Pending    a scheduling problem, not a CNI one
     node NotReady, no CNI message     the kubelet itself is down — that is
                                       exam 5, not this one

5. And note what is NOT broken: every pod already running keeps running. Its
   network namespace was configured when it started and nothing tears it
   down. Only the creation of NEW sandboxes fails. A cluster in this state
   looks fine on a dashboard and cannot deploy anything, which is precisely
   why it is worth recognising by its message."

Q[11]="Repair pod networking on '${NODE}' so that it reports Ready again.

Someone left an invalid CNI configuration file in ${CNIDIR} — it must not
be there when you are done, and a valid configuration must be in place."
PTS[11]=9
SOL[11]="ssh ${NODE}
ls -l ${CNIDIR}
rm -f ${CNIDIR}/00-broken.conflist
for f in ${CNIDIR}/*.disabled; do mv \"\$f\" \"\${f%.disabled}\"; done
systemctl restart containerd
exit
kubectl get node ${NODE} -w"
WALK[11]="1. Look at the directory. The whole fault is visible in one listing:

     ssh ${NODE}
     ls -l ${CNIDIR}
     # 00-broken.conflist
     # 05-cilium.conflist.disabled

   Two separate problems. Every real configuration has been renamed out of
   the way, and an invalid one has been left in its place.

2. Understand the ordering rule before you touch anything, because it is
   what the exam is testing. The runtime reads ${CNIDIR} in LEXICAL order
   and uses the FIRST valid configuration it finds. That is why CNI configs
   are conventionally numbered — 10-flannel.conflist, 05-cilium.conflist.
   A file named 00-anything sorts ahead of all of them.

   Files ending in .disabled are ignored: only .conf, .conflist and .json
   are considered. That is also the standard way to park a config.

3. Repair both halves:

     rm -f ${CNIDIR}/00-broken.conflist
     for f in ${CNIDIR}/*.disabled; do mv \"\$f\" \"\${f%.disabled}\"; done

4. Make the runtime re-read it. It watches the directory, so this often
   happens on its own within a minute — but do not sit waiting:

     systemctl restart containerd
     systemctl status containerd --no-pager

   Restarting containerd does not kill running containers; they are
   supervised by shim processes that outlive it.

5. There is a second, entirely legitimate route worth knowing, because it is
   how you would fix this on a cluster whose CNI is managed by a DaemonSet:
   most CNI agents WRITE their config file on startup. Delete the agent pod
   on that node and it will lay the file down again:

     kubectl -n kube-system get pods -o wide | grep ${NODE}
     kubectl -n kube-system delete pod <cni-agent-pod-on-${NODE}>

   Do not do that blindly on the control plane node as well.

6. Confirm, and be patient — the node takes up to a minute:

     kubectl get node ${NODE} -w
     kubectl get node ${NODE} \\
       -o jsonpath='{range .status.conditions[?(@.type==\"Ready\")]}{.status} {.reason}{\"\\n\"}{end}'

If it stays NotReady with the same message, the runtime has not re-read the
directory — check that no .disabled files are left and that the JSON in what
remains actually parses:

     cat ${CNIDIR}/*.conflist | python3 -m json.tool > /dev/null"

Q[12]="Prove that pod networking on '${NODE}' really is fixed, rather than just
that the node says Ready.

Create a pod called 'netcheck' in namespace '${NS}' that runs on '${NODE}',
using image 'busybox:1.36' with the command 'sleep 3600'. It must reach
Running and be given a pod IP out of the cluster's pod CIDR."
PTS[12]=7
SOL[12]="kubectl -n ${NS} run netcheck --image=busybox:1.36 \\
  --overrides='{\"spec\":{\"nodeName\":\"${NODE}\"}}' -- sleep 3600

kubectl -n ${NS} get pod netcheck -o wide
kubectl -n kube-system get pod -l component=kube-controller-manager \\
  -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\\n' | grep cluster-cidr"
WALK[12]="1. A node reporting Ready only means the runtime accepted a CNI config. It
   does not mean the config WORKS. The only proof is a new pod getting an
   address, which is why this task exists as a separate step.

2. Pin the pod to the node. Two ways, and the difference matters:

     # nodeName — bypasses the scheduler entirely
     kubectl -n ${NS} run netcheck --image=busybox:1.36 \\
       --overrides='{\"spec\":{\"nodeName\":\"${NODE}\"}}' -- sleep 3600

     # nodeSelector — asks the scheduler for that node
     kubectl -n ${NS} run netcheck --image=busybox:1.36 \\
       --overrides='{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODE}\"}}}' \\
       -- sleep 3600

   Either satisfies the task. nodeName is the blunter instrument and is
   useful precisely when you are debugging a node: it will place the pod even
   if the node is cordoned.

3. Watch what happens, because the failure mode is characteristic:

     kubectl -n ${NS} get pod netcheck -o wide -w

   With the CNI still broken it sits in ContainerCreating for ever, and the
   events say it plainly:

     kubectl -n ${NS} describe pod netcheck | tail -20
     # Failed to create pod sandbox: ... failed to set up sandbox network

   With the CNI healthy it is Running with an IP within seconds.

4. Where the pod CIDR comes from, which is the other half of this task:

     # what the control plane hands out, per node
     kubectl -n kube-system get pod -l component=kube-controller-manager \\
       -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\\n' | grep cluster-cidr

     # what kubeadm was told at init
     kubectl -n kube-system get cm kubeadm-config -o yaml | grep -i podSubnet

     # the slice allocated to this node, if the CNI uses that mechanism
     kubectl get node ${NODE} -o jsonpath='{.spec.podCIDR}{\"\\n\"}'

   These must agree with the CNI's own configuration. The classic
   installation bug is a cluster initialised with --pod-network-cidr=A and a
   CNI manifest still carrying its default B: everything installs, no error
   is printed, and pods either get no address or cannot route to each other.

   Note that .spec.podCIDR can legitimately be empty on clusters whose CNI
   does its own IP address management rather than using the per-node ranges
   the controller manager allocates — Cilium in cluster-pool mode, for one.
   Empty podCIDR is not automatically a fault.

5. Verify:

     kubectl -n ${NS} get pod netcheck -o wide
     # NAME       READY   STATUS    IP            NODE
     # netcheck   1/1     Running   192.168.1.x   ${NODE}"

Q[13]="The DaemonSet 'cni-agent' in namespace 'kube-system' is meant to be a node
networking agent, but it is not running on every node.

Change it so that it runs on ALL nodes including the control plane, uses the
host's network namespace, and is marked with the priority class reserved for
critical node-level components."
PTS[13]=6
SOL[13]="kubectl -n kube-system patch ds cni-agent --type=json -p='[
  {\"op\":\"add\",\"path\":\"/spec/template/spec/hostNetwork\",\"value\":true},
  {\"op\":\"add\",\"path\":\"/spec/template/spec/priorityClassName\",\"value\":\"system-node-critical\"},
  {\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\",\"value\":[{\"operator\":\"Exists\"}]}
]'"
WALK[13]="1. See the gap first:

     kubectl -n kube-system get ds cni-agent
     # DESIRED   CURRENT   READY   NODE SELECTOR
     # 1         1         1       <none>

     kubectl get nodes
     # controlplane   Ready
     # ${NODE}        Ready

   Two nodes, one pod. The DaemonSet controller is not ignoring the control
   plane — it created no pod there because the scheduler would refuse it.

2. Why. The control plane node carries a taint:

     kubectl get node controlplane \\
       -o jsonpath='{.spec.taints}{\"\\n\"}'
     # [{\"effect\":\"NoSchedule\",\"key\":\"node-role.kubernetes.io/control-plane\"}]

   A DaemonSet gets no exemption from taints. It needs a toleration, and a
   networking agent needs to tolerate EVERYTHING — including the
   not-ready taint, because a node without a CNI is not ready by definition,
   and an agent that refuses to run on a not-ready node can never make it
   ready. That circular dependency is why every real CNI ships this:

     tolerations:
       - operator: Exists

   A bare 'operator: Exists' with no key and no effect tolerates every taint
   there is. It is a blunt instrument and exactly right here.

3. hostNetwork: true. The agent has to program the HOST's interfaces, routes
   and iptables rules. A pod in its own network namespace cannot, and in any
   case there is no pod network yet — that is what it is there to create.
   With hostNetwork the pod uses the node's namespace and its IP is the
   node's IP.

4. priorityClassName: system-node-critical. Two built-in classes exist for
   this, and both are cluster-scoped and pre-created:

     system-node-critical     2000001000   node-level: CNI, kube-proxy
     system-cluster-critical  2000000000   cluster-level: CoreDNS, metrics

   They put the pod above everything else for preemption and protect it from
   eviction under node pressure. Evicting the CNI agent to free memory would
   take the whole node's networking with it.

5. Apply and check the count moves:

     kubectl -n kube-system patch ds cni-agent --type=json -p='[
       {\"op\":\"add\",\"path\":\"/spec/template/spec/hostNetwork\",\"value\":true},
       {\"op\":\"add\",\"path\":\"/spec/template/spec/priorityClassName\",\"value\":\"system-node-critical\"},
       {\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\",\"value\":[{\"operator\":\"Exists\"}]}
     ]'

     kubectl -n kube-system get ds cni-agent
     # DESIRED   CURRENT   READY
     # 2         2         2

   Compare that template against a real one — 'kubectl -n kube-system get ds
   kube-proxy -o yaml' — and you will find the same three settings, for the
   same three reasons."

# ─────────────── grading helpers ───────────────
jp(){ kubectl "$@" 2>/dev/null; }
nsok(){ kubectl get ns "$NS" >/dev/null 2>&1; }
nodeexists(){ kubectl get node "$NODE" >/dev/null 2>&1; }
filetrim(){ [ -f "$1" ] && tr -d '[:space:]' < "$1"; }

SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
onnode(){ $SSH "$NODE" "$@" 2>/dev/null; }

# Python is used rather than jsonpath wherever the answer is STRUCTURAL —
# "these two backends, with these weights, in the SAME rule" cannot be
# expressed as a jsonpath match, and a grep over the YAML would accept an
# object that means something different. Multi-line expressions are wrapped
# in eval("(" + expr + ")") so they can be written readably.
pyjson(){ # <kubectl args...> -- expr   (json on stdin to python)
  local expr; expr="${!#}"
  local args=("${@:1:$(($#-1))}")
  kubectl "${args[@]}" -o json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
try: sys.exit(0 if eval("("+sys.argv[1]+")") else 1)
except Exception: sys.exit(1)
' "$expr"
}
pyns(){ local kind="$1" name="$2" expr="$3"; pyjson -n "$NS" get "$kind" "$name" "$expr"; }
pycl(){ local kind="$1" name="$2" expr="$3"; pyjson get "$kind" "$name" "$expr"; }

gwapi(){ kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; }

nodecount(){ kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' '; }

# The cluster's pod CIDR, from whichever source will answer. Empty if none
# will, in which case task 12 falls back to "has an IP at all" rather than
# becoming unsolvable.
clustercidr(){
  local c
  c="$(jp -n kube-system get pod -l component=kube-controller-manager \
        -o jsonpath='{.items[0].spec.containers[0].command}' \
      | tr ',' '\n' | sed -n 's/.*--cluster-cidr=\([^"]*\).*/\1/p' | head -1)"
  [ -n "$c" ] && { printf '%s' "$c"; return; }
  jp -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' \
    | sed -n 's/.*podSubnet: *\([^ ]*\).*/\1/p' | head -1
}

check(){
  case "$1" in
    # ── Ingress ──────────────────────────────────────────
    1) pycl ingressclass nginx-ext '
d["spec"].get("controller")=="k8s.io/ingress-nginx"
and (d["metadata"].get("annotations") or {}).get(
      "ingressclass.kubernetes.io/is-default-class")=="true"' ;;

    2) nsok && pyns ingress shop '
(lambda paths:
   d["spec"].get("ingressClassName")=="nginx-ext"
   and any(p.get("path")=="/" and p.get("pathType")=="Prefix"
           and (((p.get("backend") or {}).get("service") or {}).get("name"))=="shop-v1"
           and ((((p.get("backend") or {}).get("service") or {}).get("port") or {}).get("number"))==80
           for p in paths)
   and any(p.get("path")=="/api" and p.get("pathType")=="Prefix"
           and (((p.get("backend") or {}).get("service") or {}).get("name"))=="api"
           and ((((p.get("backend") or {}).get("service") or {}).get("port") or {}).get("number"))==8080
           for p in paths)
)([p for r in (d["spec"].get("rules") or [])
     if r.get("host")=="shop.example.com"
     for p in ((r.get("http") or {}).get("paths") or [])])' ;;

    # All three faults must be gone. The deprecated annotation is checked for
    # ABSENCE, which on its own would pass against no cluster at all — hence
    # the nsok gate and the positive checks either side of it.
    3) nsok && pyns ingress legacy '
d["spec"].get("ingressClassName")=="nginx-ext"
and "kubernetes.io/ingress.class" not in (d["metadata"].get("annotations") or {})
and any(p.get("path")=="/api" and p.get("pathType")=="Prefix"
        and (((p.get("backend") or {}).get("service") or {}).get("name"))=="api"
        and ((((p.get("backend") or {}).get("service") or {}).get("port") or {}).get("number"))==8080
        for r in (d["spec"].get("rules") or [])
        for p in ((r.get("http") or {}).get("paths") or []))' ;;

    4) nsok && pyns secret shop-tls '
d.get("type")=="kubernetes.io/tls"
and bool((d.get("data") or {}).get("tls.crt"))
and bool((d.get("data") or {}).get("tls.key"))' \
       && pyns ingress shop '
any(t.get("secretName")=="shop-tls"
    and "shop.example.com" in (t.get("hosts") or [])
    for t in (d["spec"].get("tls") or []))' ;;

    # Fixed means the Service has real endpoint addresses. An EndpointSlice
    # exists for a Service that selects nothing, with "endpoints": null — so
    # "or []" everywhere, and count the ADDRESSES, not the slices.
    5) nsok && pyns svc orders '(d["spec"].get("selector") or {}).get("app")=="orders"' \
       && [ "$(jp -n "$NS" get endpointslice -l kubernetes.io/service-name=orders -o json \
              | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(0); sys.exit()
print(sum(len(e.get("addresses") or []) for s in (d.get("items") or [])
          for e in (s.get("endpoints") or [])))' 2>/dev/null)" != "0" ] ;;

    # ── Gateway API ──────────────────────────────────────
    6) gwapi && pycl gatewayclass edge-class '
d["spec"].get("controllerName")=="example.net/gateway-controller"' \
       && nsok && pyns gateway edge '
d["spec"].get("gatewayClassName")=="edge-class"
and any(l.get("name")=="http" and l.get("port")==80 and l.get("protocol")=="HTTP"
        and (((l.get("allowedRoutes") or {}).get("namespaces") or {}).get("from"))=="Same"
        for l in (d["spec"].get("listeners") or []))' ;;

    7) gwapi && nsok && pyns httproute shop-route '
any(p.get("name")=="edge" for p in (d["spec"].get("parentRefs") or []))
and "shop.example.com" in (d["spec"].get("hostnames") or [])
and any(
  any((m.get("path") or {}).get("type")=="PathPrefix"
      and (m.get("path") or {}).get("value")=="/"
      for m in (r.get("matches") or []))
  and any(b.get("name")=="shop-v1" and b.get("port")==80
          for b in (r.get("backendRefs") or []))
  for r in (d["spec"].get("rules") or []))' ;;

    # Both backends must live in the SAME rule — two rules is not a split,
    # so the weights are checked per rule rather than across the object.
    8) gwapi && nsok && pyns httproute canary '
any(p.get("name")=="edge" for p in (d["spec"].get("parentRefs") or []))
and "canary.example.com" in (d["spec"].get("hostnames") or [])
and any(
  any(b.get("name")=="shop-v1" and b.get("port")==80 and b.get("weight")==90
      for b in (r.get("backendRefs") or []))
  and any(b.get("name")=="shop-v2" and b.get("port")==80 and b.get("weight")==10
          for b in (r.get("backendRefs") or []))
  for r in (d["spec"].get("rules") or []))' ;;

    # Re-parented, and NOT gutted: the hostname, path and backend it came
    # with must survive.
    9) gwapi && nsok && pyns httproute stale-route '
any(p.get("name")=="edge" for p in (d["spec"].get("parentRefs") or []))
and "orders.example.com" in (d["spec"].get("hostnames") or [])
and any(
  any((m.get("path") or {}).get("value")=="/orders" for m in (r.get("matches") or []))
  and any(b.get("name")=="orders" for b in (r.get("backendRefs") or []))
  for r in (d["spec"].get("rules") or []))' ;;

    # ── CNI ──────────────────────────────────────────────
    # Keyword-graded, so it must be gated on a real cluster — otherwise the
    # candidate could score this with kubectl uninstalled.
    10) nodeexists && [ -f "$ANS/q10.txt" ] && python3 -c '
import sys,re
t=re.sub(r"[^a-z0-9]+"," ",open(sys.argv[1]).read().lower())
sys.exit(0 if ("cni plugin not initialized" in t
               or "networkpluginnotready" in t.replace(" ","")
               or "network plugin returns error" in t) else 1)
' "$ANS/q10.txt" ;;

    # Ready, the invalid file gone, and a real config back. All three, and
    # every one of them requires the node to answer — no ssh, no points.
    11) nodeexists || return 1
        rd="$(jp get node "$NODE" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}')"
        [ "$rd" = "True" ] || return 1
        onnode "[ ! -e $CNIDIR/00-broken.conflist ]" || return 1
        # NOT 'ls a b c': ls exits non-zero if ANY pattern is unmatched, and a
        # node with only .conflist files — which is most of them — would then
        # never pass. Ask whether at least one config of any accepted
        # extension exists.
        onnode "for f in $CNIDIR/*.conf $CNIDIR/*.conflist $CNIDIR/*.json; do [ -f \"\$f\" ] && exit 0; done; exit 1" ;;

    # Four separate readings rather than one clever expression, because each
    # of them is a different claim: it exists and runs, it runs THERE, it was
    # given an address, and the address came from the cluster's pod range.
    12) nsok && nodeexists || return 1
        [ "$(jp -n "$NS" get pod netcheck -o jsonpath='{.status.phase}')" = "Running" ] || return 1
        [ "$(jp -n "$NS" get pod netcheck -o jsonpath='{.spec.nodeName}')" = "$NODE" ] || return 1
        ip="$(jp -n "$NS" get pod netcheck -o jsonpath='{.status.podIP}')"
        [ -n "$ip" ] || return 1
        cidr="$(clustercidr)"
        # No pod CIDR discoverable anywhere? Then having a routable address
        # at all is the most that can honestly be asserted. Still fails
        # closed: the IP has to exist.
        [ -n "$cidr" ] || return 0
        python3 -c '
import ipaddress,sys
try: sys.exit(0 if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2]) else 1)
except Exception: sys.exit(0)
' "$ip" "$cidr" ;;

    13) pyjson -n kube-system get ds cni-agent '
(lambda t:
   t.get("hostNetwork") is True
   and t.get("priorityClassName")=="system-node-critical"
   and any((tol.get("operator")=="Exists" and not tol.get("key"))
           or tol.get("key")=="node-role.kubernetes.io/control-plane"
           for tol in (t.get("tolerations") or []))
)(d["spec"]["template"]["spec"])' \
        && [ -n "$(nodecount)" ] && [ "$(nodecount)" != "0" ] \
        && [ "$(jp -n kube-system get ds cni-agent -o jsonpath='{.status.desiredNumberScheduled}')" \
             = "$(nodecount)" ] ;;
    *) return 2 ;;
  esac
}

edgeinfo(){
  printf "\n%s  The edge at a glance%s\n\n" "$BO" "$N"

  printf "  %singressclasses%s\n" "$D" "$N"
  out="$(kubectl get ingressclass --no-headers 2>/dev/null)"
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /' || printf "    (none)\n"

  printf "\n  %singresses in %s%s\n" "$D" "$NS" "$N"
  out="$(kubectl -n "$NS" get ingress --no-headers 2>/dev/null)"
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /' || printf "    (none)\n"

  printf "\n  %sservices and their endpoint addresses%s\n" "$D" "$N"
  for s in $(kubectl -n "$NS" get svc -o name 2>/dev/null | cut -d/ -f2); do
    c="$(kubectl -n "$NS" get endpointslice -l "kubernetes.io/service-name=$s" -o json 2>/dev/null \
        | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(0); sys.exit()
print(sum(len(e.get("addresses") or []) for x in (d.get("items") or [])
          for e in (x.get("endpoints") or [])))' 2>/dev/null)"
    p="$(kubectl -n "$NS" get svc "$s" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
    if [ "${c:-0}" = "0" ]; then
      printf "    %-14s port %-6s %sno endpoints%s\n" "$s" "${p:-?}" "$R" "$N"
    else
      printf "    %-14s port %-6s %s%s endpoint(s)%s\n" "$s" "${p:-?}" "$G" "$c" "$N"
    fi
  done

  if gwapi; then
    printf "\n  %sgatewayclasses / gateways / httproutes%s\n" "$D" "$N"
    kubectl get gatewayclass --no-headers 2>/dev/null | sed 's/^/    /'
    kubectl -n "$NS" get gateway --no-headers 2>/dev/null | sed 's/^/    /'
    kubectl -n "$NS" get httproute --no-headers 2>/dev/null | sed 's/^/    /'
    printf "    %sPROGRAMMED stays Unknown here: no controller implements the class.%s\n" "$D" "$N"
  else
    printf "\n  %sgateway api%s\n    %sCRDs not installed — tasks 6 to 9 need them. See 'reset'.%s\n" \
      "$D" "$N" "$R" "$N"
  fi

  printf "\n  %snodes%s\n" "$D" "$N"
  kubectl get nodes --no-headers 2>/dev/null | awk '{printf "    %-16s %s\n",$1,$2}'
  msg="$(kubectl get node "$NODE" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.message}{end}' 2>/dev/null)"
  [ -n "$msg" ] && printf "    %s%s: %s%s\n" "$D" "$NODE" "$msg" "$N"

  printf "\n  %s%s on %s%s\n" "$D" "$CNIDIR" "$NODE" "$N"
  out="$(onnode "ls -1 $CNIDIR 2>/dev/null")"
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /' \
    || printf "    %s(cannot ssh to %s)%s\n" "$R" "$NODE" "$N"
  printf "\n"
}

restore(){
  if [ -x "$EX10/restore.sh" ]; then bash "$EX10/restore.sh"
  else printf "\n  %sno restore script at %s/restore.sh — run setup10.sh first%s\n\n" "$R" "$EX10" "$N" >&2; return 1; fi
}

valid_n(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]; }
need_n(){ if ! valid_n "${1:-}"; then printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2; exit 1; fi; }
show(){
  printf "\n%s┌─ Exam 10 · Task %s/%s ─ %s points%s\n%s└%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N" "$B" "$N"
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
  printf "\n%s  cka-practice · exam 10%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sIngress, the Gateway API, and the CNI — Services & Networking is 20%%.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-18s %s\n" "$CL" "list every task with its points and status"
  printf "    %-18s %s\n" "$CQ N" "show task N"
  printf "    %-18s %s\n" "$CG" "grade everything"
  printf "    %-18s %s\n" "$CE N" "walkthrough"
  printf "    %-18s %s\n" "$CS N" "just the commands"
  printf "    %-18s %s\n" "edgeinfo" "classes, ingresses, endpoints, gateways and the CNI dir"
  printf "    %-18s %s\n" "exam10restore" "repair '$NODE' and remove everything this exam made"
  printf "    %-18s %s\n\n" "$CH" "this text"
  printf "%s  THREE THINGS THAT LOOK LIKE FAILURES AND ARE NOT%s\n\n" "$BO" "$N"
  printf "    No ingress controller is installed, so every Ingress here keeps an\n"
  printf "    empty ADDRESS for ever. Nothing implements the GatewayClass either, so\n"
  printf "    Gateways stay PROGRAMMED=Unknown. Both are graded on the object you\n"
  printf "    wrote — which is how the CKA grades them too. Do not chase an address.\n\n"
  printf "    '%s' is NotReady on purpose: tasks 10 to 12 are about putting its\n" "$NODE"
  printf "    pod networking back. Pods that were already running are unaffected,\n"
  printf "    because their network namespaces were configured before the fault.\n\n"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    10 BEFORE 11   task 10 reads the node's own explanation of the fault,\n"
  printf "                   and task 11 repairs it. Fix it first and the evidence\n"
  printf "                   is gone. Capture the diagnosis before the repair — in a\n"
  printf "                   real incident that is the whole discipline.\n"
  printf "    11 BEFORE 12   nothing can get a pod IP until the CNI works.\n"
  printf "    1 BEFORE 2,3   both name the IngressClass created in task 1.\n"
  printf "    6 BEFORE 7,8,9 all three attach to the Gateway created in task 6.\n\n"
  printf "    %sFull layout: %s/README.txt%s\n\n" "$D" "$EX10" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 10 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %singress, gateway api, cni · namespace: %s · broken node: %s%s\n\n" "$D" "$NS" "$NODE" "$N"
    for i in $(seq 1 $TOTAL); do
      case "$i" in
        1)  printf "  %s── Ingress ──%s\n" "$D" "$N" ;;
        6)  printf "  %s── Gateway API ──%s\n" "$D" "$N" ;;
        10) printf "  %s── CNI ──%s\n" "$D" "$N" ;;
      esac
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   edgeinfo   ·   %s%s\n\n" "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show) need_n "${2:-}" "$CQ"; show "$2" ;;
  grade) if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"; else grade_all; fi ;;
  solve) need_n "${2:-}" "$CS"
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps) need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 10 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  edgeinfo|info) edgeinfo ;;
  restore) restore ;;
  reset) bash "$HERE/setup10.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-practice %s (exam 10)\n" "$VERSION" ;;
  *) printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"; usage; exit 1 ;;
esac
