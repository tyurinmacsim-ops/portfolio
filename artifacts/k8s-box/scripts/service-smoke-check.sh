#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/local/bin:/opt/homebrew/bin:/usr/sbin:/usr/bin:/bin:${PATH:-}"

errors=0

info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; errors=$((errors + 1)); }

require_tools() {
  command -v kubectl >/dev/null 2>&1 || { echo "Не найден kubectl" >&2; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "Не найден curl" >&2; exit 1; }

  local kube_context
  kube_context="$(kubectl config current-context 2>/dev/null || true)"
  [[ -n "${kube_context}" ]] || { echo "Не настроен kubectl context" >&2; exit 1; }
}

run_check() {
  local name="$1"
  local ns="$2"
  local svc="$3"
  local local_port="$4"
  local remote_port="$5"
  local url="$6"
  local expected="$7"

  info "Проверяем ${name} через ${ns}/${svc}"
  kubectl -n "${ns}" port-forward "svc/${svc}" "${local_port}:${remote_port}" >/tmp/pf-${name}.log 2>&1 &
  local pf_pid=$!
  local code=""
  local ok="false"

  for _ in $(seq 1 30); do
    code="$(curl -ks -o /tmp/smoke-${name}.body -w '%{http_code}' "${url}" 2>/dev/null || true)"
    if [[ "${code}" == "${expected}" ]]; then
      ok="true"
      break
    fi
    sleep 1
  done

  kill "${pf_pid}" >/dev/null 2>&1 || true
  wait "${pf_pid}" 2>/dev/null || true

  if [[ "${ok}" != "true" ]]; then
    fail "${name}: ожидался HTTP ${expected}, получен ${code:-none}"
    sed -n '1,30p' "/tmp/pf-${name}.log" >&2 || true
    return 0
  fi

  printf '[OK] %s HTTP %s\n' "${name}" "${code}"
}

service_exists() {
  local ns="$1"
  local svc="$2"
  kubectl -n "${ns}" get svc "${svc}" >/dev/null 2>&1
}

first_service_by_regex() {
  local ns="$1"
  local regex="$2"
  kubectl -n "${ns}" get svc -o json 2>/dev/null \
    | jq -r --arg regex "${regex}" '.items[] | .metadata.name | select(test($regex))' \
    | head -n1
}

main() {
  require_tools

  run_check "argocd" "argocd" "argocd-server" "18080" "80" "https://127.0.0.1:18080/" "200"
  run_check "vault" "vault" "vault-ui" "18200" "8200" "http://127.0.0.1:18200/v1/sys/health" "200"

  local grafana_svc=""
  if service_exists "monitoring" "vm-stack-grafana"; then
    grafana_svc="vm-stack-grafana"
  elif service_exists "monitoring" "kube-prometheus-stack-grafana"; then
    grafana_svc="kube-prometheus-stack-grafana"
  else
    grafana_svc="$(first_service_by_regex "monitoring" "grafana")"
  fi
  if [[ -z "${grafana_svc}" ]]; then
    fail "grafana: сервис не найден в namespace monitoring"
  else
    run_check "grafana" "monitoring" "${grafana_svc}" "13000" "80" "http://127.0.0.1:13000/login" "200"
  fi

  if kubectl -n monitoring get svc loki >/dev/null 2>&1; then
    run_check "loki" "monitoring" "loki" "13100" "3100" "http://127.0.0.1:13100/ready" "200"
  elif kubectl -n monitoring get svc loki-gateway >/dev/null 2>&1; then
    run_check "loki_gateway" "monitoring" "loki-gateway" "13100" "80" "http://127.0.0.1:13100/" "200"
  else
    fail "loki: сервис loki/loki-gateway не найден в namespace monitoring"
  fi

  if service_exists "monitoring" "vmsingle-vm-stack-victoria-metrics-k8s-stack"; then
    run_check "victoria_metrics" "monitoring" "vmsingle-vm-stack-victoria-metrics-k8s-stack" "18428" "8428" "http://127.0.0.1:18428/health" "200"
  elif service_exists "monitoring" "kube-prometheus-stack-prometheus"; then
    run_check "prometheus" "monitoring" "kube-prometheus-stack-prometheus" "19090" "9090" "http://127.0.0.1:19090/-/ready" "200"
  else
    local prom_svc
    prom_svc="$(first_service_by_regex "monitoring" "prometheus")"
    if [[ -n "${prom_svc}" ]]; then
      run_check "prometheus" "monitoring" "${prom_svc}" "19090" "9090" "http://127.0.0.1:19090/-/ready" "200"
    else
      fail "metrics backend: не найден сервис ни VictoriaMetrics, ни Prometheus"
    fi
  fi

  if (( errors > 0 )); then
    printf '\n[RESULT] FAILED: %d check(s)\n' "${errors}" >&2
    exit 1
  fi

  printf '\n[RESULT] OK\n'
}

main "$@"
