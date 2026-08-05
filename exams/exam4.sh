#!/usr/bin/env bash
# ============================================================
#  cka-practice · exam4.sh
#  13 CKA-style NetworkPolicy and network-troubleshooting
#  tasks. 100 points. Pass mark: 66.
#
#    ./exams/exam4.sh            list the tasks
#    ./exams/exam4.sh q 4        show task 4
#    ./exams/exam4.sh grade      grade everything, print the score
#    ./exams/exam4.sh grade 4    grade task 4 only
#    ./exams/exam4.sh solve 4    the commands that solve task 4
#    ./exams/exam4.sh explain 4  step-by-step walkthrough of task 4
#    ./exams/exam4.sh netcheck   run real connectivity probes
#    ./exams/exam4.sh help       full usage
#    ./exams/exam4.sh reset      re-seed the cluster (runs setup4.sh)
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers4"
EX4="$BASE/exam4"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

# The command names differ depending on whether activate.sh is loaded.
if [ -n "${EXAM_HOME:-}" ]; then
  # activate.sh is loaded: the verbs are unnumbered and act on the exam
  # selected with 'cka use'. See cka.sh.
  CL="list"; CQ="q"; CG="grade"; CE="explain"; CS="solve"; CH="examhelp"
else
  CL="./exams/exam4.sh"; CQ="./exams/exam4.sh q"; CG="./exams/exam4.sh grade"
  CE="./exams/exam4.sh explain"; CS="./exams/exam4.sh solve"; CH="./exams/exam4.sh help"
fi

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

# ─────────────────────────── 1 ───────────────────────────
Q[1]="Every pod in the namespace 'backend' must refuse all incoming traffic by
default. Outgoing traffic must NOT be affected.
Create a NetworkPolicy named 'default-deny-ingress' in that namespace."
PTS[1]=6
SOL[1]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
    - Ingress
EOF"
WALK[1]="1. Two things make a policy a 'default deny':

     podSelector: {}     an EMPTY selector, which matches every pod in the
                         namespace. Do not confuse it with omitting the
                         field — podSelector is required, and {} is how you
                         say 'all pods here'.
     no ingress rules    a policy that selects pods but allows nothing.

   Once ANY policy selects a pod, that pod is isolated for the listed
   policyTypes, and only traffic matching some allow rule gets through. With
   no rules at all, nothing gets through.

2. The trap is policyTypes. The task says egress must not be affected, so
   list Ingress and only Ingress:

     policyTypes:
       - Ingress

   Writing '- Ingress' and '- Egress' here would also cut every outbound
   connection from every pod in the namespace, including DNS, which usually
   presents as 'my app suddenly cannot resolve anything'.

3. Apply it and check what it selects:

     kubectl -n backend get netpol default-deny-ingress
     kubectl -n backend describe netpol default-deny-ingress

   In describe, look for 'Allowing ingress traffic: <none>' and
   'Not affecting egress traffic'.

4. Verify for real, if your CNI enforces policy:

     kubectl -n frontend exec client -- wget -q -T3 -O- http://\$(kubectl -n backend get pod api -o jsonpath='{.status.podIP}')

   That should now time out. Run 'netcheck' to have this done for you.

Common traps: 'podSelector:' with nothing after it is null, not {}, and
some tools treat that differently. Write the braces."

# ─────────────────────────── 2 ───────────────────────────
Q[2]="Pod 'api' in namespace 'backend' must accept traffic on TCP port 80 from pods
labelled app=web IN ITS OWN NAMESPACE, and from nowhere else.
Create a NetworkPolicy named 'allow-web-to-api'. Do not modify or delete
'default-deny-ingress'."
PTS[2]=7
SOL[2]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-api
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: web
      ports:
        - protocol: TCP
          port: 80
EOF"
WALK[2]="1. Policies are ADDITIVE, which is why the task says to leave the deny
   alone. For a given pod, the effective permission is the UNION of the
   allow rules of every policy that selects it. So:

     default-deny-ingress   selects api (it selects everything), allows nothing
     allow-web-to-api       selects api, allows web:80

   Union = web on 80. You never 'delete the deny to make room' — the deny
   contributes nothing to the union, it just makes the pod isolated.

2. A bare podSelector inside 'from' means 'in the same namespace as this
   policy'. That is the whole answer to 'in its own namespace':

     from:
       - podSelector:
           matchLabels:
             app: web

3. Restricting the port is a separate block, a sibling of 'from', not a
   child of it:

     ingress:
       - from:
           - podSelector: ...
         ports:
           - protocol: TCP
             port: 80

   Indentation is the thing that goes wrong here. 'ports' at the wrong depth
   either errors or silently becomes part of the 'from' element.

4. Verify:

     kubectl -n backend describe netpol allow-web-to-api

Common traps: leaving 'ports' out entirely allows web on EVERY port, which
is a different policy from the one asked for and scores zero. Also note
there is no 'app=web' pod in backend — the pod called web lives in
frontend — so this rule matches nothing today. That is deliberate: it is
task 3's job to notice that selecting across namespaces is a different
construct."

# ─────────────────────────── 3 ───────────────────────────
Q[3]="Pod 'api' in 'backend' must also accept TCP 80 from EVERY pod in any namespace
labelled purpose=monitoring.
Create a NetworkPolicy named 'allow-monitoring' in 'backend'."
PTS[3]=8
SOL[3]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              purpose: monitoring
      ports:
        - protocol: TCP
          port: 80
EOF"
WALK[3]="1. The single most important fact about NetworkPolicy and namespaces:
   THERE IS NO WAY TO NAME A NAMESPACE. There is no 'namespace: monitoring'
   field inside a rule. You select namespaces by their LABELS.

     kubectl get ns --show-labels | grep monitoring
     # purpose=monitoring

   If the namespace you need has no useful label, you label it:

     kubectl label ns monitoring purpose=monitoring

   (setup4.sh already did this one for you.)

2. A namespaceSelector on its own means 'all pods in every namespace with
   these labels'. That is exactly 'EVERY pod', so no podSelector is needed:

     from:
       - namespaceSelector:
           matchLabels:
             purpose: monitoring

3. Since Kubernetes 1.22 every namespace also carries an automatic label
   'kubernetes.io/metadata.name' equal to its own name. So you CAN target one
   namespace by name, indirectly:

     namespaceSelector:
       matchLabels:
         kubernetes.io/metadata.name: monitoring

   Worth knowing, and worth not reaching for when the task names a label.

4. Verify:

     kubectl -n backend describe netpol allow-monitoring

Common traps: writing podSelector where you meant namespaceSelector. Both
are valid YAML and the policy applies cleanly — it just silently matches
the wrong thing, which is the hardest kind of mistake to spot."

# ─────────────────────────── 4 ───────────────────────────
Q[4]="Pod 'db' in 'backend' must accept traffic ONLY from pods that are BOTH
labelled app=api AND running in a namespace labelled tier=backend.
Pods labelled app=api in other namespaces must NOT be allowed, and other pods
in tier=backend namespaces must NOT be allowed.
Create a NetworkPolicy named 'allow-api-to-db' in 'backend'."
PTS[4]=9
SOL[4]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              tier: backend
          podSelector:
            matchLabels:
              app: api
EOF
# ONE list element with BOTH selectors = AND.
# Two elements would mean OR, and would allow far too much."
WALK[4]="1. This is the NetworkPolicy trap, and it is pure YAML. Look at these two
   very carefully — they differ by two characters:

     # AND — one element, two selectors
     from:
       - namespaceSelector:
           matchLabels:
             tier: backend
         podSelector:
           matchLabels:
             app: api

     # OR — two elements, one selector each
     from:
       - namespaceSelector:
           matchLabels:
             tier: backend
       - podSelector:
           matchLabels:
             app: api

   The 'from' field is a LIST. Elements of the list are OR-ed. Selectors
   INSIDE one element are AND-ed. So the second version allows every pod in
   any tier=backend namespace, plus every app=api pod in this namespace —
   which is enormously more than was asked for.

2. The visual cue is the dash. In the AND version there is exactly one '-'
   in the whole block, and 'podSelector' lines up with 'namespaceSelector'
   under it. If you see two dashes, you wrote OR.

3. Verify the shape, not just that it applied:

     kubectl -n backend get netpol allow-api-to-db -o yaml

   Count the dashes under 'from:'. One is correct here.

     kubectl -n backend describe netpol allow-api-to-db

   describe renders the AND version as a single 'From:' entry listing both
   selectors together, and the OR version as two separate entries.

4. Note this rule has no 'ports', so it allows those clients on ALL ports.
   The task did not restrict ports, so that is correct — but read carefully,
   because the same task with 'on port 5432' is a different answer.

Common traps: this is the one place where an accidentally-correct-looking
policy is dangerously wrong in production, so it is a favourite of exam
writers. If you remember one thing about NetworkPolicy YAML, remember the
dash."

# ─────────────────────────── 5 ───────────────────────────
Q[5]="Every pod in 'frontend' must be blocked from making outgoing connections,
EXCEPT that DNS resolution must keep working — both UDP and TCP on port 53.
Incoming traffic must not be affected.
Create a NetworkPolicy named 'default-deny-egress' in 'frontend'."
PTS[5]=9
SOL[5]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: frontend
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
EOF"
WALK[5]="1. This is the mistake that takes down real clusters. A default-deny egress
   policy blocks DNS, because DNS is just outbound traffic to kube-dns on
   port 53. Applications then fail with 'no such host' or
   'Temporary failure in name resolution', and the policy looks innocent
   because nobody thinks of DNS as network traffic.

2. So the policy needs a rule that allows port 53. Note what is NOT here:
   there is no 'to'. An egress rule with only 'ports' means 'to anywhere, on
   these ports':

     egress:
       - ports:
           - protocol: UDP
             port: 53
           - protocol: TCP
             port: 53

3. BOTH protocols matter, and this is the second half of the trap. DNS is
   UDP for normal queries, but it falls back to TCP when a response exceeds
   512 bytes or for zone transfers. Allow only UDP and most lookups work
   while a few large ones mysteriously hang — the worst possible failure
   mode, because it looks intermittent.

4. A tighter version scopes it to the DNS service's pods, which is what you
   would actually ship:

     egress:
       - to:
           - namespaceSelector:
               matchLabels:
                 kubernetes.io/metadata.name: kube-system
             podSelector:
               matchLabels:
                 k8s-app: kube-dns
         ports:
           - protocol: UDP
             port: 53
           - protocol: TCP
             port: 53

   Note the single dash again — namespace AND pod.

5. Verify:

     kubectl -n frontend exec client -- nslookup kubernetes.default
     kubectl -n frontend exec client -- wget -q -T3 -O- http://example.com

   The lookup should work; the fetch should not.

Common traps: putting Ingress in policyTypes as well, which the task
explicitly rules out. And remember policyTypes must list Egress or the whole
egress section is dead weight — see task 8's cousin."

# ─────────────────────────── 6 ───────────────────────────
Q[6]="Pod 'web' in 'frontend' must be allowed to send traffic to the CIDR
10.0.0.0/8, EXCEPT to 10.10.10.0/24 which must stay blocked.
Create a NetworkPolicy named 'egress-ipblock' in 'frontend'."
PTS[6]=8
SOL[6]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-ipblock
  namespace: frontend
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8
            except:
              - 10.10.10.0/24
EOF"
WALK[6]="1. ipBlock is how you talk about things that are not pods — external
   services, node IPs, a database outside the cluster. It is the only
   selector in NetworkPolicy that deals in addresses rather than labels:

     to:
       - ipBlock:
           cidr: 10.0.0.0/8
           except:
             - 10.10.10.0/24

2. Two rules about 'except' that get tested:

     - every entry in 'except' must be INSIDE 'cidr'. 10.10.10.0/24 sits
       within 10.0.0.0/8, so this is valid. An except range outside the cidr
       is rejected by the API server.
     - 'except' is a list, even for one entry. Keep the dash.

3. ipBlock cannot be combined with podSelector or namespaceSelector in the
   same list element. This is invalid:

     - ipBlock: {...}
       podSelector: {...}

   If you need both, use two list elements (OR).

4. Verify:

     kubectl -n frontend describe netpol egress-ipblock

   You want 'To: 10.0.0.0/8 Except: 10.10.10.0/24'.

Common traps: pod-to-pod traffic inside the cluster often has a source IP
that ipBlock rules do NOT see the way you expect, because of SNAT on some
CNIs. ipBlock is for egress to things outside the cluster; use selectors for
pods."

# ─────────────────────────── 7 ───────────────────────────
Q[7]="Pod 'api' in 'backend' must accept TCP traffic on the whole port range
8000 to 8100 inclusive, from any pod in its own namespace.
Create a NetworkPolicy named 'allow-port-range' in 'backend'."
PTS[7]=8
SOL[7]="kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-port-range
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 8000
          endPort: 8100
EOF"
WALK[7]="1. A range is one port entry with 'port' as the start and 'endPort' as the
   end. You do not write 8000-8100, and you certainly do not write 101
   separate entries:

     ports:
       - protocol: TCP
         port: 8000
         endPort: 8100

2. Rules for endPort:

     - it must be >= port;
     - 'port' must be a NUMBER, not a named port. A named port has no
       numeric position, so a range from it is meaningless and the API
       rejects it;
     - protocol must be set (TCP, UDP or SCTP).

   endPort went stable in Kubernetes 1.25, so on any cluster the current CKA
   runs it is available — but your CNI also has to implement it. Calico and
   Cilium do.

3. 'from any pod in its own namespace' is an empty podSelector inside from:

     from:
       - podSelector: {}

   Note the difference from spec.podSelector: {} at the top level. Here it
   means 'every pod in this namespace is an allowed SOURCE'. At the top
   level it means 'this policy applies to every pod in this namespace'. Same
   syntax, completely different job.

4. Verify:

     kubectl -n backend get netpol allow-port-range -o yaml | grep -A3 ports

Common traps: omitting 'from' entirely. 'ports' with no 'from' allows those
ports from EVERYWHERE, including outside the cluster — much wider than the
task asked."

# ─────────────────────────── 8 ───────────────────────────
Q[8]="Pods labelled app=client in 'frontend' cannot reach pod 'web' on TCP 80,
even though the NetworkPolicy 'allow-client-to-web' in that namespace was
written to permit exactly that.
Find the fault and fix it, keeping the policy's name and its intent.
Do not delete it and do not create a second policy."
PTS[8]=8
SOL[8]="# The source selector says app=clientt — one letter too many.
kubectl -n frontend patch netpol allow-client-to-web --type=json \\
  -p='[{\"op\":\"replace\",\"path\":\"/spec/ingress/0/from/0/podSelector/matchLabels/app\",\"value\":\"client\"}]'
kubectl -n frontend get netpol allow-client-to-web -o jsonpath='{.spec.ingress[0].from[0].podSelector}{\"\\n\"}'"
WALK[8]="0. 'kubectl edit netpol allow-client-to-web -n frontend' does this by hand
   and is the faster answer under exam pressure. The patch below is here
   instead because it is reproducible and can be pasted.

1. Read what the policy actually says, not what it was meant to say:

     kubectl -n frontend get netpol allow-client-to-web -o yaml

   Selector fields are free-form strings. 'app: clientt' is perfectly valid
   YAML, the API server accepts it happily, and it matches no pod. The
   policy still SELECTS web, so web is isolated — and the only allow rule is
   dead. Net effect: nothing can reach web at all.

2. This is why label typos are so nasty in NetworkPolicy. There is no
   referential integrity: nothing warns you that a selector matches zero
   pods. Get into the habit of proving a selector matches what you think:

     kubectl -n frontend get pods -l app=clientt     # No resources found
     kubectl -n frontend get pods -l app=client      # pod/client

   That two-command check finds this class of bug in seconds.

3. Fix it in place. 'kubectl edit' is fine and is what most people do under
   time pressure. A patch is precise and scriptable:

     kubectl -n frontend patch netpol allow-client-to-web --type=json \\
       -p='[{\"op\":\"replace\",\"path\":\"/spec/ingress/0/from/0/podSelector/matchLabels/app\",\"value\":\"client\"}]'

4. Verify both the object and the behaviour:

     kubectl -n frontend describe netpol allow-client-to-web
     kubectl -n frontend exec client -- wget -q -T3 -O- http://\$(kubectl -n frontend get pod web -o jsonpath='{.status.podIP}')

   If you have already solved task 5, that fetch will STILL fail — and it is
   supposed to. Task 5 denies egress for every pod in frontend except port
   53, so client cannot make the outbound connection even though web now
   accepts it. Both ends are evaluated independently: the source needs an
   egress allow and the destination needs an ingress allow. Grading checks
   this policy on its own, so task 8 scores either way; 'netcheck' says the
   same thing when it notices task 5 is in place.

Common traps: deleting the policy 'fixes' connectivity, because with no
policy selecting web nothing is isolated — and it fails the task, which said
to keep it. Deleting a policy to restore traffic is worth recognising as a
diagnostic step and NOT as a fix.

The related failure worth knowing: a rule listed under 'ingress:' when
policyTypes only says '- Egress' (or vice versa) is silently ignored. Same
symptom, same lesson — the object applied, so nothing told you."

# ─────────────────────────── 9 ───────────────────────────
Q[9]="The Service 'store' in namespace 'shop' has no endpoints, so nothing can reach
it, even though its 3 backing pods are Running.
Fix the Service so that it has 3 endpoints. Do not change the pods or the
Deployment, and do not recreate the Service under a different name."
PTS[9]=7
SOL[9]="# The selector says app=stores; the pods are labelled app=store.
kubectl -n shop patch svc store -p '{\"spec\":{\"selector\":{\"app\":\"store\"}}}'"
WALK[9]="1. 'No endpoints' is the single most common Service fault, and it has one
   cause: the Service selector does not match the pod labels. Confirm the
   symptom first:

     kubectl -n shop get endpoints store
     # ENDPOINTS  <none>

     kubectl -n shop get endpointslices -l kubernetes.io/service-name=store

2. Now compare the two sides. This is the whole diagnosis:

     kubectl -n shop get svc store -o jsonpath='{.spec.selector}'
     # {\"app\":\"stores\"}
     kubectl -n shop get pods --show-labels
     # app=store,pod-template-hash=...

   'stores' vs 'store'. The Service selector must match POD labels — not the
   Deployment's name, not its labels, the pods'.

3. Fix the Service:

     kubectl -n shop patch svc store -p '{\"spec\":{\"selector\":{\"app\":\"store\"}}}'

   A merge patch on a map replaces the whole selector, which is what you
   want here.

4. Verify the endpoints appear. This is the real test, not the YAML:

     kubectl -n shop get endpoints store
     # 10.244.x.x:80,10.244.y.y:80,10.244.z.z:80

     kubectl -n shop run t --rm -it --image=busybox:1.36 --restart=Never \\
       -- wget -q -T3 -O- http://store.shop.svc.cluster.local

The debugging order worth memorising, because it isolates the layer in three
commands:

     kubectl get endpoints <svc>      empty  -> selector or pod readiness
     kubectl get pods -l <selector>   empty  -> selector is wrong
     pods listed but not Ready        -> readiness probe, not networking

A pod that is Running but not Ready is deliberately excluded from endpoints,
which is the other reason this symptom appears."

# ─────────────────────────── 10 ───────────────────────────
Q[10]="The Service 'checkout' in 'shop' HAS endpoints, but every connection to it is
refused. The backing pods serve HTTP on container port 80.
Fix the Service. Keep its name, its port 80 and its selector."
PTS[10]=7
SOL[10]="# targetPort is 8080; the containers listen on 80.
kubectl -n shop patch svc checkout --type=json \\
  -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/targetPort\",\"value\":80}]'"
WALK[10]="1. Note how this differs from task 9, because telling them apart is the
   skill. Here endpoints EXIST:

     kubectl -n shop get endpoints checkout
     # 10.244.x.x:8080,10.244.y.y:8080,...

   So the selector is fine. But look at the port in those endpoints: 8080.
   Nothing is listening there.

2. Understand the three ports on a Service, because the exam mixes them up
   on purpose:

     port         the port the SERVICE listens on (what clients dial)
     targetPort   the port on the POD that traffic is forwarded to
     nodePort     the port on every node, only for type NodePort

   'Connection refused' from a Service with healthy endpoints almost always
   means targetPort points somewhere nothing is bound.

3. Compare against what the container actually declares:

     kubectl -n shop get svc checkout -o jsonpath='{.spec.ports[0]}'
     # {\"port\":80,\"targetPort\":8080,...}
     kubectl -n shop get deploy store -o jsonpath='{.spec.template.spec.containers[0].ports}'
     # [{\"containerPort\":80,...}]

4. Fix it:

     kubectl -n shop patch svc checkout --type=json \\
       -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/targetPort\",\"value\":80}]'

5. Verify the endpoints now show :80, then actually fetch:

     kubectl -n shop get endpoints checkout
     kubectl -n shop run t --rm -it --image=busybox:1.36 --restart=Never \\
       -- wget -q -T3 -O- http://checkout.shop.svc.cluster.local

Worth knowing: targetPort can be a NAME instead of a number, matching a
named containerPort. That is more robust, because the pod can move its port
without the Service changing:

     targetPort: http

Common traps: 'connection refused' means something answered and said no —
you reached a host. 'Timed out' means nothing answered, which points at
NetworkPolicy or routing instead. The distinction saves a lot of time."

# ─────────────────────────── 11 ───────────────────────────
Q[11]="Pod 'dnsbroken' in 'shop' cannot resolve any name — not cluster Services, not
external hosts.
Make it resolve 'store.shop.svc.cluster.local' using the cluster's DNS.
Keep the pod's name and namespace. You may recreate the pod."
PTS[11]=8
SOL[11]="kubectl -n shop delete pod dnsbroken --now
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: dnsbroken
  namespace: shop
  labels:
    app: dnsbroken
spec:
  dnsPolicy: ClusterFirst
  containers:
    - name: c
      image: busybox:1.36
      command: [\"sleep\", \"86400\"]
EOF"
WALK[11]="1. See the failure, then look at where the pod thinks DNS lives:

     kubectl -n shop exec dnsbroken -- nslookup store.shop.svc.cluster.local
     kubectl -n shop exec dnsbroken -- cat /etc/resolv.conf
     # nameserver 203.0.113.53

   That is not the cluster DNS service. Compare with a healthy pod:

     kubectl -n frontend exec client -- cat /etc/resolv.conf
     # nameserver 10.96.0.10
     # search shop.svc.cluster.local svc.cluster.local cluster.local
     # options ndots:5

2. The cause is in the pod spec, not in CoreDNS:

     kubectl -n shop get pod dnsbroken -o jsonpath='{.spec.dnsPolicy}'
     # None

   'dnsPolicy: None' means 'ignore the cluster settings, use my dnsConfig
   verbatim'. The dnsConfig here points at an address that does not answer.

3. Know the four values, it is a common written question:

     ClusterFirst              the default. Cluster DNS, falling back to
                               upstream for names outside the cluster.
     ClusterFirstWithHostNet   what you need INSTEAD of ClusterFirst when
                               the pod sets hostNetwork: true — otherwise a
                               host-network pod silently uses the node's
                               resolver.
     Default                   inherit the NODE's resolv.conf. No cluster
                               DNS, so Service names do not resolve.
     None                      no cluster settings at all; dnsConfig is
                               mandatory and is used as-is.

4. dnsPolicy is immutable on a running pod, so this one has to be replaced.
   The task allows that:

     kubectl -n shop delete pod dnsbroken --now
     # recreate with dnsPolicy: ClusterFirst and no dnsConfig

5. Verify:

     kubectl -n shop exec dnsbroken -- nslookup store.shop.svc.cluster.local
     kubectl -n shop exec dnsbroken -- cat /etc/resolv.conf

If DNS is broken for EVERY pod rather than one, the cause is elsewhere and
the checks are different:

     kubectl -n kube-system get pods -l k8s-app=kube-dns
     kubectl -n kube-system get svc kube-dns
     kubectl -n kube-system logs -l k8s-app=kube-dns
     kubectl -n kube-system get cm coredns -o yaml"

# ─────────────────────────── 12 ───────────────────────────
Q[12]="The Service 'store-np' in 'shop' must be reachable on every node on port
30080, forwarding to the store pods on their port 80.
Change the existing Service — do not create a new one."
PTS[12]=7
SOL[12]="kubectl -n shop patch svc store-np -p \\
  '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":80,\"nodePort\":30080}]}}'"
WALK[12]="1. Look at what it is now:

     kubectl -n shop get svc store-np
     # TYPE ClusterIP, no external port

2. Two changes are needed: the type, and a pinned nodePort. Left to itself
   Kubernetes allocates a random port from the service-node-port-range
   (30000-32767 by default), and the task named a specific one:

     kubectl -n shop patch svc store-np -p \\
       '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":80,\"nodePort\":30080}]}}'

   When you patch 'ports' you are replacing a list, so restate the whole
   entry — port, targetPort and name included. Dropping 'name' on a
   multi-port Service is rejected; keeping it is a good habit.

3. Verify the allocation and then actually reach it:

     kubectl -n shop get svc store-np
     # TYPE NodePort   PORT(S) 80:30080/TCP

     kubectl get nodes -o wide          # take any node's INTERNAL-IP
     curl -s --max-time 3 http://<node-ip>:30080

   A NodePort answers on EVERY node, not only the one running a pod — that
   is kube-proxy's job. Testing against the 'wrong' node on purpose is a
   good way to confirm the data path.

4. If it does not answer, work down the layers:

     kubectl -n shop get endpoints store-np     # backends exist?
     kubectl -n shop get svc store-np -o yaml   # nodePort really set?
     kubectl -n kube-system get pods -l k8s-app=kube-proxy

Common traps: choosing a port outside 30000-32767 (rejected), or one already
taken by another Service (also rejected — the error names the conflict). And
remember NodePort implies ClusterIP: the Service keeps working internally by
name."

# ─────────────────────────── 13 ───────────────────────────
Q[13]="Several NetworkPolicies exist in 'backend'.
Write into ${ANS}/q13.txt the names of every NetworkPolicy in that
namespace that applies to the INGRESS of pod 'db' — one name per line, and
nothing else."
PTS[13]=8
SOL[13]="kubectl -n backend get netpol -o yaml | grep -A4 podSelector   # every selector
kubectl -n backend get pod db --show-labels     # app=db,tier=backend
# A policy applies to db's ingress if its podSelector matches those labels
# AND its policyTypes include Ingress.
cat > ${ANS}/q13.txt <<'EOF'
allow-api-to-db
db-tier-lock
default-deny-ingress
EOF"
WALK[13]="0. Reading a wall of policy YAML is easier in a pager:
   'kubectl -n backend get netpol -o yaml | less'. The solution greps
   instead only because it has to run unattended.

1. 'Which policies apply to this pod?' has no kubectl flag. You work it out
   from two things: the pod's labels, and each policy's podSelector.

     kubectl -n backend get pod db --show-labels
     # app=db,tier=backend

     kubectl -n backend get netpol
     kubectl -n backend get netpol -o yaml

2. Go through them one at a time. A policy is in scope for db's INGRESS when
   BOTH of these hold:

     - its spec.podSelector matches app=db,tier=backend
     - its spec.policyTypes contains Ingress

   For the seeded set plus what you created in tasks 1 and 4:

     default-deny-ingress  podSelector {} matches everything, Ingress   YES
     db-tier-lock          tier=backend matches db, Ingress             YES
     allow-api-to-db       app=db matches db, Ingress                   YES
     api-only              app=api does NOT match db                    no
     db-direct             app=db matches, but policyTypes is Egress    no
     allow-web-to-api      app=api does not match db                    no
     allow-monitoring      app=api does not match db                    no
     allow-port-range      app=api does not match db                    no

   Two different reasons to exclude a policy, and both are tested: the
   selector does not match, or the direction is wrong.

3. A shortcut for the selector half — ask the API which pods a selector
   matches, rather than reasoning about it:

     kubectl -n backend get pods -l tier=backend
     kubectl -n backend get pods -l app=db

4. Write the answer, one name per line:

     cat > ${ANS}/q13.txt <<'EOF'
     allow-api-to-db
     db-tier-lock
     default-deny-ingress
     EOF

   Order does not matter to the grader; the set does.

Why this is worth practising: when traffic is unexpectedly blocked, this is
the first thing you work out. 'kubectl describe netpol' one at a time is
fine, but knowing that ALL matching policies combine — and that a pod with
no matching policy is completely unrestricted — is what makes the answer
obvious instead of trial and error."

# ─────────────── grading helpers ───────────────
# NetworkPolicy correctness is structural: whether two selectors sit in one
# list element (AND) or two (OR) cannot be seen with grep, so these graders
# parse real JSON. python3 is already a requirement of the suite.
np(){ kubectl -n "$1" get netpol "$2" -o json 2>/dev/null; }

# pyjson <json-producing-command...> -- <python expression on 'd'>
# Prints nothing; exit 0 if the expression is truthy.
npassert(){ # ns name expr
  local json; json="$(np "$1" "$2")"
  [ -n "$json" ] || return 1
  printf '%s' "$json" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
spec = d.get("spec") or {}
# The assertions are written across several lines for readability. A bare
# multi-line expression is not valid Python unless it is bracketed, so wrap
# it here rather than making every caller remember the parentheses.
try:
    sys.exit(0 if eval("(" + sys.argv[1] + ")") else 1)
except Exception:
    sys.exit(1)
' "$3"
}

svcjson(){ kubectl -n "$1" get svc "$2" -o json 2>/dev/null; }
svcassert(){ # ns name expr
  local json; json="$(svcjson "$1" "$2")"
  [ -n "$json" ] || return 1
  printf '%s' "$json" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
spec = d.get("spec") or {}
try:
    sys.exit(0 if eval("(" + sys.argv[1] + ")") else 1)
except Exception:
    sys.exit(1)
' "$3"
}

# Endpoint count, via EndpointSlice (Endpoints is deprecated but still
# present; slices are what modern kube-proxy consumes).
# A Service whose selector matches nothing still gets an EndpointSlice — one
# with "endpoints": null. So these fields exist but are None rather than
# absent, and .get(k, []) hands back None. Every list access here therefore
# uses 'or []', and the whole thing degrades to 0 rather than a traceback.
epcount(){ # ns svc -> number of ready addresses
  kubectl -n "$1" get endpointslice -l "kubernetes.io/service-name=$2" -o json 2>/dev/null \
    | python3 -c '
import json,sys
n = 0
try:
    d = json.load(sys.stdin)
    for s in d.get("items") or []:
        for ep in s.get("endpoints") or []:
            if (ep.get("conditions") or {}).get("ready", True):
                n += len(ep.get("addresses") or [])
except Exception:
    n = 0
print(n)
'
}

epport(){ # ns svc -> first port in the slice, empty if there is none
  kubectl -n "$1" get endpointslice -l "kubernetes.io/service-name=$2" -o json 2>/dev/null \
    | python3 -c '
import json,sys
out = ""
try:
    d = json.load(sys.stdin)
    for s in d.get("items") or []:
        for p in s.get("ports") or []:
            out = p.get("port", ""); break
        if out != "": break
except Exception:
    out = ""
print(out)
'
}

nsexists(){ kubectl get ns "$1" >/dev/null 2>&1; }
podfield(){ kubectl -n "$1" get pod "$2" -o jsonpath="{$3}" 2>/dev/null; }

check(){
  case "$1" in
    # podSelector {} = all pods; Ingress only, so egress stays untouched;
    # and no ingress rules at all, which is what makes it a deny.
    1) npassert backend default-deny-ingress \
         'spec.get("podSelector")=={} and spec.get("policyTypes")==["Ingress"] and not spec.get("ingress")' ;;

    2) npassert backend allow-web-to-api '
(spec.get("podSelector",{}).get("matchLabels",{}).get("app")=="api")
and ("Ingress" in (spec.get("policyTypes") or []))
and len(spec.get("ingress") or [])>=1
and any(
    len(r.get("from") or [])==1
    and (r["from"][0].get("podSelector",{}).get("matchLabels",{}).get("app")=="web")
    and ("namespaceSelector" not in r["from"][0])
    and any(str(p.get("port"))=="80" and p.get("protocol","TCP")=="TCP" for p in (r.get("ports") or []))
    for r in spec["ingress"]
)' ;;

    3) npassert backend allow-monitoring '
(spec.get("podSelector",{}).get("matchLabels",{}).get("app")=="api")
and ("Ingress" in (spec.get("policyTypes") or []))
and any(
    any(
        f.get("namespaceSelector",{}).get("matchLabels",{}).get("purpose")=="monitoring"
        for f in (r.get("from") or [])
    )
    and any(str(p.get("port"))=="80" for p in (r.get("ports") or []))
    for r in (spec.get("ingress") or [])
)' ;;

    # The AND/OR trap: exactly ONE from-element carrying BOTH selectors.
    4) npassert backend allow-api-to-db '
(spec.get("podSelector",{}).get("matchLabels",{}).get("app")=="db")
and ("Ingress" in (spec.get("policyTypes") or []))
and any(
    len(r.get("from") or [])==1
    and r["from"][0].get("namespaceSelector",{}).get("matchLabels",{}).get("tier")=="backend"
    and r["from"][0].get("podSelector",{}).get("matchLabels",{}).get("app")=="api"
    for r in (spec.get("ingress") or [])
)' ;;

    # Egress deny that still permits DNS on BOTH udp/53 and tcp/53.
    5) npassert frontend default-deny-egress '
spec.get("podSelector")=={}
and spec.get("policyTypes")==["Egress"]
and any(
    any(str(p.get("port"))=="53" and p.get("protocol")=="UDP" for p in (r.get("ports") or []))
    for r in (spec.get("egress") or [])
)
and any(
    any(str(p.get("port"))=="53" and p.get("protocol")=="TCP" for p in (r.get("ports") or []))
    for r in (spec.get("egress") or [])
)' ;;

    6) npassert frontend egress-ipblock '
(spec.get("podSelector",{}).get("matchLabels",{}).get("app")=="web")
and ("Egress" in (spec.get("policyTypes") or []))
and any(
    any(
        t.get("ipBlock",{}).get("cidr")=="10.0.0.0/8"
        and "10.10.10.0/24" in (t.get("ipBlock",{}).get("except") or [])
        for t in (r.get("to") or [])
    )
    for r in (spec.get("egress") or [])
)' ;;

    7) npassert backend allow-port-range '
(spec.get("podSelector",{}).get("matchLabels",{}).get("app")=="api")
and ("Ingress" in (spec.get("policyTypes") or []))
and any(
    any(f.get("podSelector")=={} for f in (r.get("from") or []))
    and any(
        str(p.get("port"))=="8000" and str(p.get("endPort"))=="8100"
        and p.get("protocol")=="TCP"
        for p in (r.get("ports") or [])
    )
    for r in (spec.get("ingress") or [])
)' ;;

    # The typo is fixed, the policy still exists under its own name, and its
    # intent (web <- client on 80) is intact.
    8) npassert frontend allow-client-to-web '
(spec.get("podSelector",{}).get("matchLabels",{}).get("app")=="web")
and ("Ingress" in (spec.get("policyTypes") or []))
and any(
    any(f.get("podSelector",{}).get("matchLabels",{}).get("app")=="client"
        for f in (r.get("from") or []))
    and any(str(p.get("port"))=="80" for p in (r.get("ports") or []))
    for r in (spec.get("ingress") or [])
)' ;;

    # Behavioural: the endpoints have to actually populate.
    9) svcassert shop store 'spec.get("selector",{}).get("app")=="store"' \
       && [ "$(epcount shop store)" -ge 3 ] ;;

    10) svcassert shop checkout '
any(str(p.get("targetPort"))in("80","http") and str(p.get("port"))=="80"
    for p in (spec.get("ports") or []))
and spec.get("selector",{}).get("app")=="store"' \
        && [ "$(epport shop checkout)" = "80" ] ;;

    11) [ "$(podfield shop dnsbroken .spec.dnsPolicy)" = "ClusterFirst" ] \
        && [ "$(podfield shop dnsbroken .status.phase)" = "Running" ] \
        && ! kubectl -n shop get pod dnsbroken -o json 2>/dev/null \
             | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if (d["spec"].get("dnsConfig") or {}).get("nameservers") else 1)' ;;

    12) svcassert shop store-np '
spec.get("type")=="NodePort"
and any(str(p.get("nodePort"))=="30080" and str(p.get("targetPort"))=="80"
        for p in (spec.get("ports") or []))' \
        && [ "$(epcount shop store-np)" -ge 1 ] ;;

    # Set comparison, order-insensitive, whitespace-tolerant.
    13) [ -f "$ANS/q13.txt" ] && python3 -c '
import sys
want = {"default-deny-ingress","db-tier-lock","allow-api-to-db"}
got = {l.strip() for l in open(sys.argv[1]) if l.strip()}
sys.exit(0 if got==want else 1)
' "$ANS/q13.txt" ;;
    *) return 2 ;;
  esac
}

# ─────────────── real connectivity probes ───────────────
# Grading reads the objects you wrote, which works on any cluster. This
# command is the other half: it drives actual traffic, so you can watch a
# policy take effect. It needs a CNI that enforces policy.
netcheck(){
  local enf="unknown"
  [ -f "$EX4/enforcement" ] && enf="$(cat "$EX4/enforcement")"

  printf "\n%s  Connectivity probes%s\n\n" "$BO" "$N"
  case "$enf" in
    enforced) printf "  %sCNI enforces NetworkPolicy — these results are meaningful.%s\n\n" "$D" "$N" ;;
    not-enforced)
      printf "  %s!%s %sThis cluster's CNI does NOT enforce NetworkPolicy.%s\n" "$Y" "$N" "$BO" "$N"
      printf "  %sEverything below will show as reachable no matter what you write.%s\n" "$D" "$N"
      printf "  %sGrading is unaffected — it reads your policy objects.%s\n\n" "$D" "$N" ;;
    *) printf "  %senforcement unknown; re-run setup4.sh to probe again%s\n\n" "$D" "$N" ;;
  esac

  probe(){ # label from-ns from-pod target-ns target-pod
    local ip; ip="$(podfield "$4" "$5" .status.podIP)"
    if [ -z "$ip" ]; then
      printf "  %s?%s  %-34s %starget pod not found%s\n" "$Y" "$N" "$1" "$D" "$N"; return
    fi
    if kubectl -n "$2" exec "$3" -- wget -q -T3 -O- "http://$ip" >/dev/null 2>&1; then
      printf "  %s→%s  %-34s %sreachable%s\n" "$G" "$N" "$1" "$G" "$N"
    else
      printf "  %s✗%s  %-34s %sblocked / no answer%s\n" "$R" "$N" "$1" "$R" "$N"
    fi
  }

  probe "frontend/client -> frontend/web" frontend client frontend web
  probe "frontend/client -> backend/api"  frontend client backend api
  probe "monitoring/prom -> backend/api"  monitoring prom  backend api
  probe "netdebug/tester -> backend/db"   netdebug tester  backend db

  # Both ends of a connection are evaluated independently, and this catches
  # everyone out at least once: task 5 denies egress for every pod in
  # frontend, so once it is solved the two frontend/client probes read
  # 'blocked' no matter how correct task 8's ingress rule is. That is the
  # single most useful thing NetworkPolicy teaches, so say it rather than
  # letting a correct answer look like a failure.
  if kubectl -n frontend get netpol default-deny-egress >/dev/null 2>&1; then
    printf "\n  %sNote:%s task 5's egress deny is in place, so frontend/client can only\n" "$Y" "$N"
    printf "  reach port 53. Both directions must allow a connection — the two\n"
    printf "  frontend/client probes above SHOULD read blocked, even with task 8 fixed.\n"
  fi

  printf "\n  %sDNS:%s\n" "$BO" "$N"
  for spec in "frontend client" "shop dnsbroken"; do
    set -- $spec
    if kubectl -n "$1" exec "$2" -- nslookup store.shop.svc.cluster.local >/dev/null 2>&1; then
      printf "  %s→%s  %-34s %sresolves%s\n" "$G" "$N" "$1/$2" "$G" "$N"
    else
      printf "  %s✗%s  %-34s %sfails%s\n" "$R" "$N" "$1/$2" "$R" "$N"
    fi
  done

  printf "\n  %sService endpoints:%s\n" "$BO" "$N"
  for s in store checkout store-np; do
    printf "  %s   %-34s %s ready address(es), port %s\n" " " "shop/$s" \
      "$(epcount shop "$s")" "$(epport shop "$s")"
  done
  printf "\n"
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
  printf "\n%s┌─ Exam 4 · Task %s/%s ─ %s points%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N"
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
  printf "\n%s  cka-practice · exam 4%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %sNetworkPolicy and network troubleshooting. No Helm.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-20s %s\n" "$CL"           "list every task with its points and status"
  printf "    %-20s %s\n" "$CQ N"         "show task N"
  printf "    %-20s %s\n" "$CG"           "grade everything and print the score"
  printf "    %-20s %s\n" "$CG N"         "grade task N only"
  printf "    %-20s %s\n" "$CE N"         "step-by-step walkthrough, with the reasoning"
  printf "    %-20s %s\n" "$CS N"         "just the commands, no explanation"
  printf "    %-20s %s\n" "netcheck"      "drive real traffic and print what got through"
  printf "    %-20s %s\n" "$CH"           "this text"
  printf "    %-20s %s\n" "$CL version"   "print the exam suite version"
  printf "    %-20s %s\n\n" "$CL reset"   "re-seed exam 4 from scratch"
  printf "%s  HOW THIS ONE IS GRADED%s\n\n" "$BO" "$N"
  printf "    The NetworkPolicy tasks are graded by parsing the policy you\n"
  printf "    wrote, because a policy object IS cluster state and because the\n"
  printf "    distinctions that matter — one 'from' element versus two, UDP\n"
  printf "    versus TCP on 53 — are structural. Grading reads real JSON, so\n"
  printf "    an almost-right policy scores zero, exactly as it should.\n\n"
  printf "    The troubleshooting tasks are graded on BEHAVIOUR: endpoints have\n"
  printf "    to populate, the port has to be right, DNS has to resolve.\n\n"
  printf "    %sNetworkPolicy is only enforced if your CNI implements it.%s\n" "$BO" "$N"
  printf "    setup4.sh probes this by applying a deny and testing a real\n"
  printf "    connection, and records the answer in %s/enforcement\n" "$EX4"
  printf "    On a cluster with no policy controller (plain Flannel, for\n"
  printf "    instance) every policy applies cleanly and blocks nothing.\n"
  printf "    Grading still works; 'netcheck' will tell you it is not real.\n\n"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    1 → 2, 3, 4   the deny in task 1 is what makes the allows meaningful\n"
  printf "    9 before 10   task 9 teaches endpoints; task 10 assumes you can read them\n"
  printf "    13 last       it asks you to inventory the policies you have created\n\n"
  printf "%s  THE CLUSTER YOU ARE GIVEN%s\n\n" "$BO" "$N"
  printf "    frontend    web (app=web) · client (app=client)        ns label tier=frontend\n"
  printf "    backend     api (app=api) · db (app=db)                ns label tier=backend\n"
  printf "    monitoring  prom (app=prom)                            ns label purpose=monitoring\n"
  printf "    shop        deploy/store ×3 · 3 broken Services        ns label tier=shop\n"
  printf "    netdebug    tester (app=tester)\n\n"
  printf "    Full notes, including how to test by hand: %s/README.txt\n\n" "$EX4"
  printf "    %sIf the Killercoda session expires, run %s/setup4.sh again.%s\n\n" "$D" "$HERE" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 4 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %sNetworkPolicy + network troubleshooting%s\n\n" "$D" "$N"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   netcheck   ·   %s%s\n\n" \
      "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
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
    printf "\n%s┌─ Exam 4 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  netcheck|check|info) netcheck ;;
  reset) bash "$HERE/setup4.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-practice %s (exam 4)\n" "$VERSION" ;;
  *)
    printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"
    usage; exit 1 ;;
esac
