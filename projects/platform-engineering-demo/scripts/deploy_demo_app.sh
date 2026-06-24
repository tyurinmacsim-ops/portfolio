#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-demo-api:local}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl kustomize "${REPO_ROOT}/k8s/demo-api" \
  | sed "s#demo-api:latest#${IMAGE}#g" \
  | kubectl apply -f -

kubectl rollout status deployment/demo-api -n apps --timeout=180s
