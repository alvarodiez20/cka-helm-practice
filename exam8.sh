#!/usr/bin/env bash
# ============================================================
#  cka-helm-practice · exam8.sh
#  13 CKA-style cluster lifecycle tasks: etcd backup and
#  restore, kubeadm, certificates, node maintenance.
#  100 points. Pass mark: 66.
#
#    ./exam8.sh q 4 · grade · explain 4 · cplaneinfo
# ============================================================
set -uo pipefail

BASE="${HOME}"
ANS="$BASE/answers8"
EX8="$BASE/exam8"
NODE="${CKA_NODE:-node01}"
# Overridable so the exam works on a cluster with a non-standard layout,
# and so the graders can be tested without a real control plane.
SNAP="${CKA_E8_SNAP:-/opt/etcd-backup.db}"
RESTORED="${CKA_E8_RESTORED:-/var/lib/etcd-restored}"
PKITAR="${CKA_E8_PKITAR:-/opt/pki-etcd.tar}"
MANIFESTS="${CKA_E8_MANIFESTS:-/etc/kubernetes/manifests}"
PKIDIR="${CKA_E8_PKI:-/etc/kubernetes/pki}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo "unknown")"

if [ -t 1 ]; then G=$'\e[32m';R=$'\e[31m';Y=$'\e[33m';B=$'\e[36m';D=$'\e[2m';BO=$'\e[1m';N=$'\e[0m'
else G="";R="";Y="";B="";D="";BO="";N=""; fi

if [ -n "${EXAM_HOME:-}" ]; then
  # activate.sh is loaded: the verbs are unnumbered and act on the exam
  # selected with 'cka use'. See cka.sh.
  CL="list"; CQ="q"; CG="grade"; CE="explain"; CS="solve"; CH="examhelp"
else
  CL="./exam8.sh"; CQ="./exam8.sh q"; CG="./exam8.sh grade"
  CE="./exam8.sh explain"; CS="./exam8.sh solve"; CH="./exam8.sh help"
fi

ETCDFLAGS="--endpoints=https://127.0.0.1:2379 \\
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\
  --cert=/etc/kubernetes/pki/etcd/server.crt \\
  --key=/etc/kubernetes/pki/etcd/server.key"

TOTAL=13
Q=(); PTS=(); SOL=(); WALK=()

Q[1]="Take a snapshot of the cluster's etcd datastore and save it to ${SNAP}.
Use etcdctl with the certificates etcd itself uses."
PTS[1]=10
SOL[1]="export ETCDCTL_API=3
etcdctl ${ETCDFLAGS} \\
  snapshot save ${SNAP}"
WALK[1]="1. Everything you need is in etcd's own static pod manifest — do not guess
   the paths, read them:

     grep -E 'listen-client-urls|cert-file|key-file|trusted-ca-file|data-dir' \\
       ${MANIFESTS}/etcd.yaml

     --listen-client-urls=https://127.0.0.1:2379,...
     --cert-file=/etc/kubernetes/pki/etcd/server.crt
     --key-file=/etc/kubernetes/pki/etcd/server.key
     --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
     --data-dir=/var/lib/etcd

   That is the whole answer to 'which flags do I pass'. The mapping is:

     --trusted-ca-file  ->  --cacert
     --cert-file        ->  --cert
     --key-file         ->  --key
     --listen-client-urls -> --endpoints

2. etcd speaks mutual TLS, so all three certificate flags are required. A
   snapshot without them fails with 'context deadline exceeded', which looks
   like a network problem and is actually an auth problem — that misdirection
   costs people a lot of time.

3. Take it:

     export ETCDCTL_API=3
     etcdctl ${ETCDFLAGS} \\
       snapshot save ${SNAP}

   ETCDCTL_API=3 is unnecessary on etcd 3.4+ where v3 is the default, but
   setting it costs nothing and saves you on an older cluster.

4. Verify — and this is the step that proves the file is real rather than a
   zero-byte artifact of a failed command:

     etcdutl snapshot status ${SNAP} --write-out=table
     ls -lh ${SNAP}

5. A snapshot is a point-in-time copy of the whole keyspace: every object in
   the cluster. It is the backup that matters — losing etcd loses the
   cluster, whereas losing a worker loses nothing permanent.

Common traps: running this on a worker node. etcd's certificates only exist
on the control plane, so the whole task has to happen there."

Q[2]="Write into ${ANS}/q2.txt the REVISION recorded in the snapshot at
${SNAP}, as reported by the snapshot status output.
Just the number."
PTS[2]=7
SOL[2]="etcdutl snapshot status ${SNAP} --write-out=json | \\
  python3 -c 'import json,sys; print(json.load(sys.stdin)[\"revision\"])' > ${ANS}/q2.txt
# or read it from the table:
etcdutl snapshot status ${SNAP} --write-out=table"
WALK[2]="1. 'snapshot status' reads the file itself — it does not talk to a running
   etcd, so it needs no certificates and works on a copied snapshot anywhere:

     etcdutl snapshot status ${SNAP} --write-out=table

     +----------+----------+------------+------------+
     |   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
     +----------+----------+------------+------------+
     | 8f3a1b2c |    47210 |       1284 |     5.2 MB |
     +----------+----------+------------+------------+

2. The four columns and what each is for:

     HASH         a checksum of the contents; two snapshots with the same
                  hash are identical
     REVISION     etcd's global logical clock. It only ever increases, so it
                  tells you how recent a snapshot is relative to another.
     TOTAL KEYS   roughly, how many objects the cluster had
     TOTAL SIZE   the on-disk size of the database

3. For scripting, ask for JSON:

     etcdutl snapshot status ${SNAP} --write-out=json
     # {\"hash\":...,\"revision\":47210,\"totalKey\":1284,\"totalSize\":...}

     etcdutl snapshot status ${SNAP} --write-out=json \\
       | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"revision\"])' \\
       > ${ANS}/q2.txt

4. etcdctl vs etcdutl, since both appear in documentation:

     etcdctl   talks to a RUNNING etcd over the network. Needs certificates.
     etcdutl   works on FILES on disk — status, restore, defrag of a
               snapshot. Needs nothing.

   'etcdctl snapshot status' and 'etcdctl snapshot restore' still work but
   are deprecated in favour of etcdutl, and print a warning saying so.

Common traps: a snapshot status of 0 keys and revision 0 means the save
failed and left an empty file. Check this before trusting a backup — which
is the real lesson."

Q[3]="Restore the snapshot at ${SNAP} into a NEW data directory at
${RESTORED}.
Do not touch the running etcd, do not stop the API server, and do not modify
/var/lib/etcd."
PTS[3]=10
SOL[3]="etcdutl snapshot restore ${SNAP} --data-dir=${RESTORED}
ls ${RESTORED}/member      # snap  wal"
WALK[3]="1. Restoring writes a brand new etcd data directory from the snapshot. It
   does not contact a running etcd at all, so no certificates and no
   endpoints are involved:

     etcdutl snapshot restore ${SNAP} --data-dir=${RESTORED}

   The directory must NOT already exist — etcd refuses to overwrite one, so
   'rm -rf' it first if you are retrying.

2. Verify the shape. A valid etcd data dir has a member directory containing
   snap and wal:

     ls -R ${RESTORED} | head
     ${RESTORED}/member/snap
     ${RESTORED}/member/wal

3. Why the task stops here, and what the real procedure is. Restoring a
   directory is only half of a recovery; the other half is the CUTOVER, and
   it is deliberately out of scope because it would take this cluster down:

     # 1. stop the API server by moving its manifest out of the way
     mv ${MANIFESTS}/kube-apiserver.yaml /tmp/

     # 2. stop etcd the same way
     mv ${MANIFESTS}/etcd.yaml /tmp/

     # 3. swap the data directory
     mv /var/lib/etcd /var/lib/etcd.old
     mv ${RESTORED} /var/lib/etcd

     # 4. put the manifests back; the kubelet restarts both
     mv /tmp/etcd.yaml /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

   The alternative, which the exam also accepts, is to leave the restored
   directory where it is and point etcd at it by editing --data-dir and the
   hostPath volume in ${MANIFESTS}/etcd.yaml. Either way the
   kubelet does the restarting — you never run systemctl against etcd.

4. The two things that go wrong in a real restore:

     - forgetting that a restore RESETS the cluster to the snapshot's moment.
       Everything created since is gone. That is the point, and it still
       surprises people.
     - restoring on a multi-member cluster without --initial-cluster and
       --initial-advertise-peer-urls, which produces a member that will not
       join. Single-node kubeadm clusters do not need them.

Common traps: using 'etcdctl snapshot restore' with --endpoints and
certificates. Restore is a local file operation; those flags are ignored and
their presence suggests a misunderstanding of what restore does."

Q[4]="Write into ${ANS}/q4.txt the value of etcd's --data-dir flag, exactly as it
appears in its static pod manifest.
Just the path."
PTS[4]=7
SOL[4]="grep -oP '(?<=--data-dir=)\\S+' ${MANIFESTS}/etcd.yaml > ${ANS}/q4.txt
# or simply:
grep data-dir ${MANIFESTS}/etcd.yaml"
WALK[4]="1. The control plane's real configuration is in four files, and reading them
   is a skill in itself:

     ls /etc/kubernetes/manifests/
     etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml
     kube-scheduler.yaml

2. Pull the flag:

     grep -- --data-dir ${MANIFESTS}/etcd.yaml
     #     - --data-dir=/var/lib/etcd

     grep -oP '(?<=--data-dir=)\\S+' ${MANIFESTS}/etcd.yaml \\
       > ${ANS}/q4.txt

   Without GNU grep's -P:

     awk -F= '/--data-dir/{print \$2}' ${MANIFESTS}/etcd.yaml

3. The other etcd flags worth being able to find on demand, because a
   troubleshooting question will ask for one of them:

     --data-dir                    where the database lives
     --listen-client-urls          where clients connect
     --listen-peer-urls            where other members connect
     --advertise-client-urls       what it tells clients to use
     --cert-file / --key-file      its server certificate
     --trusted-ca-file             the CA it trusts
     --initial-cluster             the members, at bootstrap

4. And the corresponding question on the API server side, which is the other
   half of the same picture:

     grep -- --etcd-servers ${MANIFESTS}/kube-apiserver.yaml
     grep -- --advertise-address ${MANIFESTS}/kube-apiserver.yaml

   If --etcd-servers does not match where etcd is actually listening, the API
   server crashloops and the cluster is gone. That is a classic exam fault.

Note the manifest is also mounted into the pod, so 'kubectl -n kube-system
describe pod etcd-\$(hostname)' shows the same flags — useful when you are
not on the node."

Q[5]="Back up etcd's PKI directory — /etc/kubernetes/pki/etcd — into a tar archive
at ${PKITAR}.
The archive must contain etcd's CA certificate."
PTS[5]=7
SOL[5]="tar -cf ${PKITAR} -C /etc/kubernetes/pki etcd
tar -tf ${PKITAR} | head"
WALK[5]="1. A snapshot of etcd's DATA is not a complete backup. Without the
   certificates that etcd and the API server use to talk to it, a restored
   database is unusable — so the PKI goes with it:

     ls /etc/kubernetes/pki/etcd/
     ca.crt  ca.key  healthcheck-client.crt  healthcheck-client.key
     peer.crt  peer.key  server.crt  server.key

2. Archive it:

     tar -cf ${PKITAR} -C /etc/kubernetes/pki etcd

   '-C /etc/kubernetes/pki etcd' stores the paths as 'etcd/ca.crt' rather
   than '/etc/kubernetes/pki/etcd/ca.crt'. Relative paths in an archive are
   the right habit: absolute ones are refused or silently stripped on
   extraction, and they make the archive impossible to restore elsewhere.

3. Verify the contents rather than just the file's existence:

     tar -tf ${PKITAR}
     # etcd/
     # etcd/ca.crt
     # etcd/server.crt
     # ...

4. What a genuine control plane backup consists of, worth knowing as a set:

     the etcd snapshot            all cluster state
     /etc/kubernetes/pki/         every CA and certificate
     /etc/kubernetes/*.conf       admin, controller-manager, scheduler,
                                  kubelet kubeconfigs
     /etc/kubernetes/manifests/   the static pod definitions

   Restoring the snapshot without /etc/kubernetes/pki gives you a cluster
   whose certificates no longer match its CA — every component fails TLS,
   and the symptom is a total, baffling outage.

Common traps: 'tar -cf backup.tar /etc/kubernetes/pki/etcd' works but warns
'removing leading / from member names', and the resulting archive extracts
to a relative path anyway. Use -C."

Q[6]="Write into ${ANS}/q6.txt the NAME of the certificate that expires soonest,
exactly as kubeadm lists it in the leftmost column of its expiration report."
PTS[6]=8
SOL[6]="kubeadm certs check-expiration
# read the CERTIFICATE column with the smallest RESIDUAL TIME
echo apiserver > ${ANS}/q6.txt   # whichever it turns out to be"
WALK[6]="1. Run the report:

     kubeadm certs check-expiration

     CERTIFICATE                EXPIRES                RESIDUAL TIME  ...
     admin.conf                 Jul 29, 2027 12:00 UTC 364d
     apiserver                  Jul 29, 2027 12:00 UTC 364d
     apiserver-etcd-client      ...
     apiserver-kubelet-client   ...
     controller-manager.conf    ...
     etcd-healthcheck-client    ...
     etcd-peer                  ...
     etcd-server                ...
     front-proxy-client         ...
     scheduler.conf             ...

     CERTIFICATE AUTHORITY      EXPIRES                RESIDUAL TIME
     ca                         Jul 27, 2036 12:00 UTC 9y
     etcd-ca                    ...
     front-proxy-ca             ...

2. The structure of that output is the lesson:

     leaf certificates    ONE YEAR by default
     certificate authorities  TEN YEARS

   So a kubeadm cluster that is quietly left alone stops working after about
   a year, when the leaf certificates expire — while the CAs are still fine.
   'x509: certificate has expired or is not yet valid' on every kubectl
   command, on a cluster nobody touched, is this.

3. Sorting it, since eyeballing residual time is error-prone:

     kubeadm certs check-expiration | sort -k2 -M

   In practice the leaves are all issued at the same moment by kubeadm, so
   they usually share an expiry date — pick the first of them.

4. Note that 'kubeadm upgrade' renews all the leaf certificates as a side
   effect. A cluster upgraded once a year never hits this; one that is not
   upgraded does.

Common traps: reporting a CA. The CAs are in a separate table at the bottom
and have ten-year lifetimes, so they are never the soonest."

Q[7]="Renew the 'apiserver-kubelet-client' certificate with kubeadm, so that it is
freshly issued."
PTS[7]=8
SOL[7]="kubeadm certs renew apiserver-kubelet-client
kubeadm certs check-expiration | grep apiserver-kubelet-client"
WALK[7]="1. Renew one certificate by name:

     kubeadm certs renew apiserver-kubelet-client

   kubeadm re-issues it from the existing CA, writes it to
   /etc/kubernetes/pki/, and keeps the same subject and SANs. The CA is
   untouched, so nothing else in the cluster has to change.

2. Verify the new dates:

     kubeadm certs check-expiration | grep apiserver-kubelet-client
     openssl x509 -in ${PKIDIR}/apiserver-kubelet-client.crt \\
       -noout -dates

   'notBefore' should be today. That is the proof it was actually re-issued
   rather than merely inspected.

3. The important half people forget: RENEWING IS NOT ENOUGH. A running
   process holds its certificate in memory, so the component must restart
   before it uses the new one. For static pods that means moving the
   manifest out and back:

     mv ${MANIFESTS}/kube-apiserver.yaml /tmp/
     sleep 20
     mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

   The kubelet notices the file and rebuilds the pod. This task renews a
   certificate the API server uses to talk to kubelets, so a restart is
   needed for it to take effect — the grader only checks the renewal, but
   knowing the second step is the point.

4. The variants:

     kubeadm certs renew all              every leaf certificate
     kubeadm certs renew <name>           one
     kubeadm certs check-expiration       before and after

   'renew all' plus a control plane restart is the standard annual
   maintenance, and is what you would do on the exam if asked to fix an
   expired cluster.

5. Note what renewal does NOT cover: the kubelet's own client certificate at
   /var/lib/kubelet/pki/. Those rotate automatically when
   rotateCertificates is on, which it is by default on kubeadm. And
   /etc/kubernetes/admin.conf embeds a certificate too — 'renew all'
   refreshes it, but any copy you made to ~/.kube/config does not update
   itself.

Common traps: renewing and then reporting success without restarting
anything. On the exam, if the task says 'the cluster must work again',
renewal alone will not have achieved it."

Q[8]="The worker node '${NODE}' is going down for maintenance.
Evict every workload from it safely, so that nothing but DaemonSet pods is left
running there. DaemonSet pods are managed elsewhere and must not block you."
PTS[8]=8
SOL[8]="kubectl drain ${NODE} --ignore-daemonsets --delete-emptydir-data"
WALK[8]="1. drain is cordon plus eviction, and the two flags are almost always
   required in practice:

     kubectl drain ${NODE} --ignore-daemonsets --delete-emptydir-data

     --ignore-daemonsets      DaemonSet pods are not evictable — the
                              controller would immediately recreate them on
                              the same node. Without this flag drain refuses
                              to start at all.
     --delete-emptydir-data   pods with emptyDir volumes hold data that
                              cannot be moved. Without this, drain stops and
                              tells you which pod.

2. Watch what it does:

     kubectl get nodes                    # Ready,SchedulingDisabled
     kubectl get pods -A -o wide --field-selector spec.nodeName=${NODE}
     kubectl -n drain-lab get pods -o wide  # rescheduled elsewhere

   Note drain uses the EVICTION API, not delete. That is what makes it safe:
   evictions respect PodDisruptionBudgets, so a workload that must keep a
   quorum will slow the drain down rather than being torn apart.

3. When a drain hangs, it is one of three things, and the message names it:

     a PodDisruptionBudget      would be violated. Correct behaviour —
                                either wait, or fix the budget.
     a bare pod                 not managed by any controller, so nothing
                                would recreate it. Needs --force, and you
                                are accepting that it is simply gone.
     a stuck terminating pod    finalizers or a hung container runtime

4. Nothing here is permanent: drain sets .spec.unschedulable and moves pods.
   The node is still Ready, still a cluster member, and task 9 puts it back.

The full maintenance cycle, which is what the exam actually tests:

     kubectl drain ${NODE} --ignore-daemonsets --delete-emptydir-data
     # ... upgrade the kubelet, patch the OS, reboot ...
     kubectl uncordon ${NODE}

Common traps: 'kubectl delete node' instead of drain. That removes the node
object from the cluster and requires a kubeadm join to undo — a completely
different and much worse operation."

Q[9]="Maintenance on '${NODE}' is finished. Return it to normal service so the
scheduler will use it again."
PTS[9]=6
SOL[9]="kubectl uncordon ${NODE}"
WALK[9]="1. Undo the cordon half of the drain:

     kubectl uncordon ${NODE}
     kubectl get nodes        # Ready, with no SchedulingDisabled

2. Note what uncordon does NOT do: it does not bring back the pods that were
   evicted. Those were rescheduled elsewhere when you drained, and they stay
   where they are. The node simply becomes eligible again for FUTURE
   scheduling.

   If you want the existing workload rebalanced onto it, you have to give
   the scheduler a reason — delete a pod, or scale the Deployment. Kubernetes
   has no built-in rebalancer.

     kubectl -n drain-lab rollout restart deploy parked

3. The three states a node can be in, which are worth keeping distinct:

     Ready                        healthy, accepting pods
     Ready,SchedulingDisabled     healthy, cordoned. Existing pods run on.
     NotReady                     the kubelet is not reporting. Exam 5.

   A cordoned node is not a broken node, and the fix is completely different.

4. The whole kubeadm node upgrade sequence, of which this is the last step —
   worth memorising as one block, because the exam asks for it as one:

     kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
     # on the node:
     apt-get update && apt-get install -y kubeadm=<version>
     kubeadm upgrade node                    # 'kubeadm upgrade apply' on
                                             # the control plane instead
     apt-get install -y kubelet=<version> kubectl=<version>
     systemctl daemon-reload && systemctl restart kubelet
     # back on the control plane:
     kubectl uncordon <node>

Common traps: forgetting the uncordon. The upgrade works, everything looks
healthy, and the node quietly never receives another pod."

Q[10]="Write into ${ANS}/q10.txt the newest Kubernetes version that
'kubeadm upgrade plan' reports this cluster could be upgraded to.
Just the version string, for example v1.35.2"
PTS[10]=8
SOL[10]="kubeadm upgrade plan
# read the highest version in the 'you can upgrade to' table
kubeadm upgrade plan 2>/dev/null | grep -oE 'v1\\.[0-9]+\\.[0-9]+' | sort -V | tail -1 \\
  > ${ANS}/q10.txt"
WALK[10]="1. 'upgrade plan' is read-only — it changes nothing, it just reports what is
   available and what would happen:

     kubeadm upgrade plan

     [upgrade/versions] Cluster version: v1.35.1
     [upgrade/versions] kubeadm version: v1.35.1
     [upgrade/versions] Target version: v1.35.2
     ...
     COMPONENT   CURRENT   TARGET
     kube-apiserver  v1.35.1  v1.35.2

2. Extract the newest version it mentions:

     kubeadm upgrade plan 2>/dev/null \\
       | grep -oE 'v1\\.[0-9]+\\.[0-9]+' | sort -V | tail -1 > ${ANS}/q10.txt

   'sort -V' sorts version strings properly — plain sort puts v1.35.10 before
   v1.35.2, which is exactly the sort of thing that costs a mark.

3. The upgrade rules the plan is enforcing, and which the exam tests:

     - upgrade ONE MINOR VERSION at a time. 1.33 to 1.35 is not allowed;
       you go 1.33 -> 1.34 -> 1.35.
     - kubeadm must be upgraded FIRST, and it must be at least the version
       you are upgrading the cluster to.
     - the kubelet may lag the API server by up to three minor versions, but
       must never be ahead.
     - control plane first, then workers.

4. The actual upgrade, for context — the plan is step 2 of this:

     apt-get install -y kubeadm=1.35.2-*     # control plane
     kubeadm upgrade plan
     kubeadm upgrade apply v1.35.2
     apt-get install -y kubelet=1.35.2-* kubectl=1.35.2-*
     systemctl daemon-reload && systemctl restart kubelet

     # each worker, one at a time:
     kubectl drain <node> --ignore-daemonsets
     apt-get install -y kubeadm=1.35.2-*
     kubeadm upgrade node
     apt-get install -y kubelet=1.35.2-*
     systemctl daemon-reload && systemctl restart kubelet
     kubectl uncordon <node>

Note 'kubeadm upgrade apply' on the control plane, 'kubeadm upgrade node' on
workers — different subcommands, and mixing them up is a common error.

If the plan reports no newer version, the answer is the current one. That is
a legitimate outcome on a freshly-built lab cluster."

Q[11]="A new worker is being added to the cluster.
Write into ${ANS}/q11.txt the complete 'kubeadm join' command that a new
node would run, including a valid token and the CA certificate hash."
PTS[11]=8
SOL[11]="kubeadm token create --print-join-command > ${ANS}/q11.txt
cat ${ANS}/q11.txt"
WALK[11]="1. One command produces the whole thing, token included:

     kubeadm token create --print-join-command

     kubeadm join 172.30.1.2:6443 --token abcdef.0123456789abcdef \\
       --discovery-token-ca-cert-hash sha256:1234...

   That is the answer. The long way round is worth knowing too, because it
   shows what the pieces are:

     kubeadm token list                     # existing tokens
     kubeadm token create                   # a new one
     openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \\
       | openssl rsa -pubin -outform der 2>/dev/null \\
       | openssl dgst -sha256 -hex | sed 's/^.* //'

2. What each part is for, which explains why joining is safe over an
   untrusted network:

     the token           authenticates the NEW NODE to the cluster. It
                         expires after 24 hours by default.
     the ca-cert-hash    lets the new node verify it is talking to the RIGHT
                         cluster, before it trusts anything the API server
                         sends. Mutual distrust, resolved in both directions.

3. Tokens expiring is the single most common reason a join fails, and the
   error is unhelpful:

     kubeadm token list                    # empty, or TTL in the past
     kubeadm token create --print-join-command   # just make a new one

4. For joining another CONTROL PLANE node rather than a worker you also need
   a certificate key, which is separate and also expires — after two hours:

     kubeadm init phase upload-certs --upload-certs
     kubeadm join ... --control-plane --certificate-key <key>

Common traps: writing the join command from memory with a stale token from
the original 'kubeadm init' output. Tokens are short-lived by design;
generate a fresh one."

Q[12]="Write into ${ANS}/q12.txt the names of the four static pod manifest files
that define this cluster's control plane — one filename per line, and nothing
else."
PTS[12]=6
SOL[12]="ls /etc/kubernetes/manifests/ > ${ANS}/q12.txt
cat ${ANS}/q12.txt
# etcd.yaml
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml"
WALK[12]="1. On a kubeadm cluster the control plane is four static pods, and their
   definitions are ordinary files:

     ls /etc/kubernetes/manifests/
     etcd.yaml
     kube-apiserver.yaml
     kube-controller-manager.yaml
     kube-scheduler.yaml

     ls /etc/kubernetes/manifests/ > ${ANS}/q12.txt

2. Static pods are owned by the kubelet, not the API server, and everything
   surprising about them follows from that:

     - the kubelet watches the directory and starts whatever is in it. There
       is no scheduler involved and no Deployment.
     - it creates a MIRROR pod in the API server so you can see it. That
       mirror is read-only.
     - 'kubectl delete pod kube-apiserver-controlplane' deletes the mirror.
       The kubelet recreates it seconds later from the same file.
     - to stop one, MOVE THE FILE:

         mv ${MANIFESTS}/kube-apiserver.yaml /tmp/

       and to start it again, move it back. That is the standard way to
       take the API server down deliberately, and the standard accident.

3. Which directory the kubelet watches is itself configurable, and worth
   checking rather than assuming:

     grep staticPodPath /var/lib/kubelet/config.yaml
     # staticPodPath: /etc/kubernetes/manifests

4. This is why a kubeadm control plane can bootstrap itself: the kubelet
   needs no API server to start these, so etcd and the API server come up
   from files on disk before there is a cluster to schedule them.

Common traps: the task asks for filenames, so 'kube-apiserver.yaml', not
'kube-apiserver' and not the pod names, which have the node name appended."

Q[13]="Write into ${ANS}/q13.txt the value of the kube-apiserver's
--advertise-address flag.
Just the address."
PTS[13]=7
SOL[13]="grep -oP '(?<=--advertise-address=)\\S+' \\
  ${MANIFESTS}/kube-apiserver.yaml > ${ANS}/q13.txt"
WALK[13]="1. Same technique as task 4, on the other manifest:

     grep -- --advertise-address ${MANIFESTS}/kube-apiserver.yaml
     #     - --advertise-address=172.30.1.2

     grep -oP '(?<=--advertise-address=)\\S+' \\
       ${MANIFESTS}/kube-apiserver.yaml > ${ANS}/q13.txt

2. What it does: it is the address the API server publishes to everything
   else — it lands in the kubernetes.default Service's endpoint, and in the
   kubeconfigs kubeadm generates. It is not merely cosmetic.

3. Why it is a classic exam fault. If a node's IP changes — a rebuilt VM, a
   migrated control plane — and this flag still names the old address, the
   API server may start and yet nothing can reach it usefully. The symptom is
   'connection refused' or a TLS name mismatch from every component at once.

   The related fields that must agree, and which are the thing to check
   together:

     kube-apiserver.yaml   --advertise-address
     kube-apiserver.yaml   --etcd-servers
     /etc/kubernetes/*.conf   the 'server:' URL in every kubeconfig
     the apiserver certificate's SANs, which must include the address

     openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text \\
       | grep -A1 'Subject Alternative Name'

   If the address is not in the SANs, clients get
   'x509: certificate is valid for ..., not <address>'. Fixing that needs the
   certificate regenerated, not just the flag edited:

     kubeadm init phase certs apiserver --apiserver-advertise-address=<new>

4. The other flags on this manifest worth being able to find:

     --secure-port                 6443
     --service-cluster-ip-range    the Service CIDR
     --authorization-mode          Node,RBAC
     --enable-admission-plugins    what admission controllers are on

Common traps: reporting the address with the port, or reporting
--bind-address (often 0.0.0.0) instead. They are different flags and mean
different things: bind is where it listens, advertise is what it tells
others."

# ─────────────── grading helpers ───────────────
filetrim(){ [ -f "$1" ] && tr -d '[:space:]' < "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }
snapstatus(){ # prints the snapshot's revision, or nothing
  if have etcdutl; then etcdutl snapshot status "$SNAP" --write-out=json 2>/dev/null
  elif have etcdctl; then ETCDCTL_API=3 etcdctl snapshot status "$SNAP" --write-out=json 2>/dev/null
  fi | python3 -c '
import json,sys
try: print(json.load(sys.stdin).get("revision",""))
except Exception: pass
'
}
manifestflag(){ # file flag -> value
  [ -f "$1" ] || return 1
  sed -n "s/.*--$2=\([^ \"]*\).*/\1/p" "$1" | head -1
}
nodefield(){ kubectl get node "$NODE" -o jsonpath="{$1}" 2>/dev/null; }
nodeexists(){ kubectl get node "$NODE" >/dev/null 2>&1; }

check(){
  case "$1" in
    # A snapshot that exists but has revision 0 is a failed save. Check the
    # content, not the filename.
    1) [ -s "$SNAP" ] && [ -n "$(snapstatus)" ] && [ "$(snapstatus)" -gt 0 ] 2>/dev/null ;;
    2) [ -n "$(filetrim "$ANS/q2.txt")" ] \
       && [ "$(filetrim "$ANS/q2.txt")" = "$(snapstatus)" ] ;;
    3) [ -d "$RESTORED/member/snap" ] && [ -d "$RESTORED/member/wal" ] ;;
    4) [ -n "$(filetrim "$ANS/q4.txt")" ] \
       && [ "$(filetrim "$ANS/q4.txt")" \
            = "$(manifestflag ${MANIFESTS}/etcd.yaml data-dir)" ] ;;
    5) [ -s "$PKITAR" ] && tar -tf "$PKITAR" 2>/dev/null | grep -q 'etcd/ca\.crt$' ;;
    6) [ -n "$(filetrim "$ANS/q6.txt")" ] \
       && have kubeadm \
       && kubeadm certs check-expiration 2>/dev/null \
          | awk 'NR>1 && $1!~/^CERTIFICATE/ {print $1}' \
          | grep -qx "$(filetrim "$ANS/q6.txt")" ;;
    # Renewed means issued recently — check notBefore is within 24h.
    7) [ -f "$PKIDIR/apiserver-kubelet-client.crt" ] \
       && python3 - "$PKIDIR/apiserver-kubelet-client.crt" <<'PY'
import subprocess,sys,datetime
try:
    out=subprocess.run(["openssl","x509","-in",sys.argv[1],"-noout","-startdate"],
      capture_output=True,text=True).stdout.strip()
    d=datetime.datetime.strptime(out.split("=",1)[1].strip(),"%b %d %H:%M:%S %Y %Z")
    # utcnow() is deprecated on Python 3.12 and prints a warning straight
    # into the grader's output. Compare explicitly in UTC instead.
    now=datetime.datetime.now(datetime.timezone.utc)
    age=(now - d.replace(tzinfo=datetime.timezone.utc)).total_seconds()
    sys.exit(0 if 0 <= age <= 86400 else 1)
except Exception:
    sys.exit(1)
PY
       ;;
    # Tasks 8 and 9 undo each other by design. Grading the CORDON fails
    # (task 9 clears it) and so does grading the EVICTION — a live run showed
    # that once the node is uncordoned the evicted pods are rescheduled
    # straight back onto it. So this check LATCHES: the first time the drained
    # state is observed it records the fact, and the record is proof
    # afterwards. Re-seeding with setup8.sh clears the marker.
    8) if [ -f "$EX8/.drained" ]; then return 0; fi
       nodeexists \
       && [ "$(kubectl get pods -A --field-selector "spec.nodeName=$NODE" \
              -o json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(1); sys.exit()
n=0
for p in d.get("items") or []:
    owners=[o.get("kind") for o in (p.get("metadata") or {}).get("ownerReferences") or []]
    if "DaemonSet" in owners: continue
    if (p.get("status") or {}).get("phase") in ("Succeeded","Failed"): continue
    if (p.get("metadata") or {}).get("namespace")=="kube-system": continue
    n+=1
print(n)
')" = "0" ] || return 1
       # Latch it: see the comment above.
       mkdir -p "$EX8" && : > "$EX8/.drained" ;;
    # 'Returned to service' only means something if it LEFT service first.
    # Without the task-8 precondition this passes for free on any cluster
    # where the node was never drained at all.
    9) check 8 \
       && case "$(nodefield .spec.unschedulable)" in ""|false) return 0 ;; *) return 1 ;; esac ;;
    10) [ -n "$(filetrim "$ANS/q10.txt")" ] \
        && printf '%s' "$(filetrim "$ANS/q10.txt")" | grep -Eq '^v1\.[0-9]+\.[0-9]+$' ;;
    11) [ -f "$ANS/q11.txt" ] \
        && grep -q 'kubeadm join' "$ANS/q11.txt" \
        && grep -q -- '--token' "$ANS/q11.txt" \
        && grep -q -- '--discovery-token-ca-cert-hash' "$ANS/q11.txt" \
        && grep -qE 'sha256:[0-9a-f]{64}' "$ANS/q11.txt" ;;
    12) [ -f "$ANS/q12.txt" ] && python3 -c '
import sys
want={"etcd.yaml","kube-apiserver.yaml","kube-controller-manager.yaml","kube-scheduler.yaml"}
got={l.strip() for l in open(sys.argv[1]) if l.strip()}
sys.exit(0 if got==want else 1)
' "$ANS/q12.txt" ;;
    13) [ -n "$(filetrim "$ANS/q13.txt")" ] \
        && [ "$(filetrim "$ANS/q13.txt")" \
             = "$(manifestflag ${MANIFESTS}/kube-apiserver.yaml advertise-address)" ] ;;
    *) return 2 ;;
  esac
}

cplaneinfo(){
  printf "\n%s  Control plane at a glance%s\n\n" "$BO" "$N"
  printf "  %sstatic pod manifests%s\n" "$D" "$N"
  ls "$MANIFESTS"/ 2>/dev/null | sed 's/^/    /' \
    || printf "    %s(not on the control plane node)%s\n" "$R" "$N"
  printf "\n  %setcd%s\n" "$D" "$N"
  printf "    data-dir        %s\n" "$(manifestflag ${MANIFESTS}/etcd.yaml data-dir || echo '?')"
  printf "    client urls     %s\n" "$(manifestflag ${MANIFESTS}/etcd.yaml listen-client-urls || echo '?')"
  printf "    snapshot        %s\n" "$([ -s "$SNAP" ] && echo "$SNAP  rev $(snapstatus)" || echo '<none>')"
  printf "    restored dir    %s\n" "$([ -d "$RESTORED/member" ] && echo "$RESTORED" || echo '<none>')"
  printf "\n  %sapiserver%s\n" "$D" "$N"
  printf "    advertise       %s\n" "$(manifestflag ${MANIFESTS}/kube-apiserver.yaml advertise-address || echo '?')"
  printf "    etcd-servers    %s\n" "$(manifestflag ${MANIFESTS}/kube-apiserver.yaml etcd-servers || echo '?')"
  printf "\n  %scertificates expiring soonest%s\n" "$D" "$N"
  if have kubeadm; then
    kubeadm certs check-expiration 2>/dev/null | sed -n '2,6p' | cut -c1-92 | sed 's/^/    /'
  else printf "    (kubeadm not found)\n"; fi
  printf "\n  %snodes%s\n" "$D" "$N"
  kubectl get nodes 2>/dev/null | sed 's/^/    /' || printf "    (unreachable)\n"
  printf "\n"
}

valid_n(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le "$TOTAL" ]; }
need_n(){ if ! valid_n "${1:-}"; then printf "\n  %sgive a task number between 1 and %s%s   e.g.  %s 4\n\n" "$R" "$TOTAL" "$N" "${2:-$CQ}" >&2; exit 1; fi; }
show(){
  printf "\n%s┌─ Exam 8 · Task %s/%s ─ %s points%s\n%s└%s\n" "$B" "$1" "$TOTAL" "${PTS[$1]}" "$N" "$B" "$N"
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
  printf "\n%s  cka-helm-practice · exam 8%s — %s tasks, 100 points, pass mark 66\n" "$BO" "$N" "$TOTAL"
  printf "  %setcd, kubeadm, certificates and node maintenance.%s\n\n" "$D" "$N"
  printf "%s  COMMANDS%s\n\n" "$BO" "$N"
  printf "    %-18s %s\n" "$CL" "list every task with its points and status"
  printf "    %-18s %s\n" "$CQ N" "show task N"
  printf "    %-18s %s\n" "$CG" "grade everything"
  printf "    %-18s %s\n" "$CE N" "walkthrough"
  printf "    %-18s %s\n" "$CS N" "just the commands"
  printf "    %-18s %s\n" "cplaneinfo" "manifests, etcd flags, cert expiry, nodes"
  printf "    %-18s %s\n\n" "$CH" "this text"
  printf "%s  NOTHING HERE IS BROKEN%s\n\n" "$BO" "$N"
  printf "    Unlike exams 5 and 6, this one plants no faults. Every task is an\n"
  printf "    operation you carry out — take a snapshot, restore it, back up the\n"
  printf "    PKI, renew a certificate, drain a node.\n\n"
  printf "%s  WHY THE RESTORE USES A NEW DIRECTORY%s\n\n" "$BO" "$N"
  printf "    A real etcd restore replaces /var/lib/etcd with the API server\n"
  printf "    stopped. That would take kubectl down and the grader with it, so\n"
  printf "    task 3 restores into %s instead —\n" "$RESTORED"
  printf "    which is the first half of the real procedure and what the exam\n"
  printf "    usually asks for. Task 3's walkthrough gives the cutover in full.\n\n"
  printf "%s  RUN THIS ON THE CONTROL PLANE%s\n\n" "$BO" "$N"
  printf "    etcd's certificates and the static pod manifests are local files.\n"
  printf "    Tasks 1-7 and 12-13 need them; 8-11 work from anywhere.\n\n"
  printf "%s  ORDER MATTERS%s\n\n" "$BO" "$N"
  printf "    1 → 2 → 3   nothing to report or restore without a snapshot\n"
  printf "    8 → 9       drain, then uncordon. Do them as a pair — task 8 is graded on
                the eviction, which survives the uncordon, so both can pass.\n\n"
  printf "    %sFull command reference: %s/README.txt%s\n\n" "$D" "$EX8" "$N"
}

case "${1:-list}" in
  list)
    printf "\n%s  Exam 8 for the CKA%s — %s tasks · 100 points · pass mark 66\n" "$BO" "$N" "$TOTAL"
    printf "  %setcd · kubeadm · certificates · node maintenance%s\n\n" "$D" "$N"
    for i in $(seq 1 $TOTAL); do
      m=" "; check "$i" >/dev/null 2>&1 && m="${G}✔${N}"
      first="$(echo "${Q[$i]}" | head -1)"
      printf "  [%s] %2s  %-3s pts  %s\n" "$m" "$i" "${PTS[$i]}" "${first:0:58}"
    done
    printf "\n  %s%s N   ·   %s   ·   %s N   ·   cplaneinfo   ·   %s%s\n\n" "$D" "$CQ" "$CG" "$CE" "$CH" "$N" ;;
  q|show) need_n "${2:-}" "$CQ"; show "$2" ;;
  grade) if [ $# -ge 2 ]; then need_n "$2" "$CG"; printf "\n"; grade_one "$2"; printf "\n"; else grade_all; fi ;;
  solve) need_n "${2:-}" "$CS"
    printf "\n%s  Solution to task %s:%s\n\n%s\n\n" "$Y" "$2" "$N" "${SOL[$2]}"
    printf "  %swant the reasoning too?  %s %s%s\n\n" "$D" "$CE" "$2" "$N" ;;
  explain|walk|steps) need_n "${2:-}" "$CE"
    printf "\n%s┌─ Exam 8 · Task %s/%s ─ walkthrough%s\n%s└%s\n\n" "$B" "$2" "$TOTAL" "$N" "$B" "$N"
    echo "${Q[$2]}"
    printf "\n%s  ── Step by step ──%s\n\n%s\n\n" "$Y" "$N" "${WALK[$2]}"
    printf "%s  ── The commands, together ──%s\n\n%s\n\n" "$Y" "$N" "${SOL[$2]}"
    printf "  %scheck your work:  %s %s%s\n\n" "$D" "$CG" "$2" "$N" ;;
  cplaneinfo|info) cplaneinfo ;;
  reset) bash "$HERE/setup8.sh" ;;
  help|-h|--help) usage ;;
  version|-v|--version) printf "cka-helm-practice %s (exam 8)\n" "$VERSION" ;;
  *) printf "\n  %sunknown command: %s%s\n" "$R" "$1" "$N"; usage; exit 1 ;;
esac
