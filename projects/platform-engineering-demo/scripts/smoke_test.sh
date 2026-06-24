#!/usr/bin/env bash
set -euo pipefail

kubectl rollout status deployment/demo-api -n apps --timeout=180s
kubectl get servicemonitor demo-api -n apps >/dev/null

kubectl -n apps port-forward svc/demo-api 18080:80 >/tmp/demo-api-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} >/dev/null 2>&1 || true' EXIT

sleep 5

curl --fail --silent http://127.0.0.1:18080/healthz >/dev/null
curl --fail --silent http://127.0.0.1:18080/api/v1/orders/42 >/dev/null
curl --fail --silent http://127.0.0.1:18080/metrics | grep -q "demo_api_http_requests_total"
