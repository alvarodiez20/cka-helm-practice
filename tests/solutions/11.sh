#!/usr/bin/env bash
# ============================================================
#  Reference solution for exam 11 (Kustomize).
#
#  Run by scripts/solve-and-grade.sh. It does what a candidate
#  who got every task right would do, in order, and grades
#  after each one. A correct run ends 100/100.
#
#  Exam 11 needs this file rather than the generic path in
#  solve-and-grade.sh, because most of its SOL entries are a
#  comment describing what to add to a kustomization plus the
#  apply — they are instructions, not a runnable script. Every
#  YAML below is exactly what the corresponding 'solve N'
#  describes.
#
#  Verified 2026-08-04 on a Killercoda CKA playground:
#  Kubernetes v1.35.1, kustomize v5.7.1 vendored into kubectl.
# ============================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E="$ROOT/exams/exam11.sh"
EX=$HOME/exam11; ANS=$HOME/answers11
g(){ printf '  T%-3s ' "$1"; bash "$E" grade "$1" 2>&1 | grep -oE '(✔|✘).*(correct|unsolved.*)' | head -1; }

echo "=== T1: resources ==="
cat > $EX/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF
g 1

echo "=== T2: namespace + namePrefix, apply ==="
cat > $EX/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kust-lab
namePrefix: web-
resources:
  - deployment.yaml
  - service.yaml
EOF
kubectl apply -k $EX/base >/dev/null; g 2

echo "=== T3: labels/pairs, selector untouched ==="
cat > $EX/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kust-lab
namePrefix: web-
labels:
  - pairs:
      app.kubernetes.io/part-of: storefront
    includeTemplates: true
resources:
  - deployment.yaml
  - service.yaml
EOF
kubectl apply -k $EX/base 2>&1 | tail -2; g 3

echo "=== T4: images transformer ==="
cat >> $EX/base/kustomization.yaml <<'EOF'
images:
  - name: nginx
    newTag: 1.27-alpine
EOF
kubectl apply -k $EX/base >/dev/null; g 4

echo "=== T5: replicas transformer ==="
cat >> $EX/base/kustomization.yaml <<'EOF'
replicas:
  - name: shop
    count: 4
EOF
kubectl apply -k $EX/base >/dev/null; g 5

echo "=== T6/T7: configMapGenerator + disableNameSuffixHash ==="
cat >> $EX/base/kustomization.yaml <<'EOF'
configMapGenerator:
  - name: app-settings
    literals:
      - LOG_LEVEL=debug
      - REGION=eu-west-1
  - name: feature-flags
    options:
      disableNameSuffixHash: true
    literals:
      - CHECKOUT_V2=true
EOF
kubectl apply -k $EX/base >/dev/null; g 6; g 7
kubectl -n kust-lab get cm | grep -v kube-root

echo "=== T8: secretGenerator ==="
cat >> $EX/base/kustomization.yaml <<'EOF'
secretGenerator:
  - name: db-auth
    literals:
      - password=s3cr3t
EOF
kubectl apply -k $EX/base >/dev/null; g 8
kubectl -n kust-lab get secret

echo "=== T9: overlay + strategic merge patch ==="
mkdir -p $EX/overlays/prod
cat > $EX/overlays/prod/resources-patch.yaml <<'EOF'
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
cat > $EX/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - path: resources-patch.yaml
EOF
kubectl apply -k $EX/overlays/prod >/dev/null; g 9

echo "=== T10: JSON 6902 patch ==="
cat > $EX/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - path: resources-patch.yaml
  - target:
      kind: Service
      name: shop
    patch: |-
      - op: add
        path: /metadata/annotations
        value:
          monitoring.example.com/scrape: "true"
EOF
kubectl apply -k $EX/overlays/prod >/dev/null; g 10

echo "=== T11: render without applying ==="
kubectl kustomize $EX/overlays/prod > $ANS/q11.yaml; g 11

echo "=== T12: fix the broken kustomization (three stacked faults) ==="
echo "--- fault 1 (kind) ---"; kubectl kustomize $EX/broken 2>&1 | head -2
sed -i 's/^kind: Kustomize$/kind: Kustomization/' $EX/broken/kustomization.yaml
echo "--- fault 2 (resource path) ---"; kubectl kustomize $EX/broken 2>&1 | head -2
sed -i 's/  - deploy.yaml/  - deployment.yaml/' $EX/broken/kustomization.yaml
echo "--- fault 3 (namePrefix shape) ---"; kubectl kustomize $EX/broken 2>&1 | head -2
printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nnamePrefix: batch-\nresources:\n  - deployment.yaml\n  - service.yaml\n' > $EX/broken/kustomization.yaml
echo "--- after ---"; kubectl kustomize $EX/broken 2>&1 | grep -E '^kind:|name:' | head -4
g 12

echo "=== T13: object count ==="
kubectl kustomize $EX/overlays/prod | grep -c '^kind:' > $ANS/q13.txt
echo "  counted: $(cat $ANS/q13.txt)"; g 13

echo
echo "================= FINAL ================="
bash "$E" grade
