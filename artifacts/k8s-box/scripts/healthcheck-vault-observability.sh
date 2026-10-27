#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${SCRIPT_DIR}/../../infrastructure}"
VAULT_NS="${VAULT_NS:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
ALLOW_VAULT_OUTOFSYNC_IN_TEST="${ALLOW_VAULT_OUTOFSYNC_IN_TEST:-true}"
NODE_READINESS_WARN_ONLY="${NODE_READINESS_WARN_ONLY:-true}"

errors=0
warnings=0

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; errors=$((errors + 1)); }

require_tools() {
  command -v kubectl >/dev/null 2>&1 || { echo "Не найден kubectl" >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo "Не найден jq" >&2; exit 1; }
  command -v helm >/dev/null 2>&1 || { echo "Не найден helm" >&2; exit 1; }

  local kube_context
  kube_context="$(kubectl config current-context 2>/dev/null || true)"
  [[ -n "${kube_context}" ]] || { echo "Не настроен kubectl context" >&2; exit 1; }
}

read_value() {
  local file="$1"
  local key="$2"
  [[ -f "${file}" ]] || return 1
  grep -E "^[[:space:]]*${key}:" "${file}" \
    | head -n1 \
    | awk -F ':' '{print $2}' \
    | cut -d '#' -f1 \
    | xargs
}

render_observability_apps() {
  local chart_dir="${INFRA_REPO_DIR}/observability"
  [[ -d "${chart_dir}" ]] || return 1

  # Берем ожидаемый набор дочерних Application из актуального Helm chart,
  # чтобы operational-скрипт не расходился с логикой infrastructure.
  helm template observability "${chart_dir}" 2>/dev/null \
    | awk '
        /^kind: Application$/ { in_app=1; in_meta=0; next }
        in_app && /^metadata:$/ { in_meta=1; next }
        in_app && in_meta && /^  name:[[:space:]]*/ {
          sub(/^  name:[[:space:]]*/, "", $0)
          print
          in_app=0
          in_meta=0
        }
      '
}

check_namespace() {
  local ns="$1"
  if ! kubectl get namespace "${ns}" >/dev/null 2>&1; then
    fail "Отсутствует namespace: ${ns}"
    return
  fi
  local phase
  phase="$(kubectl get namespace "${ns}" -o jsonpath='{.status.phase}')"
  if [[ "${phase}" != "Active" ]]; then
    fail "У namespace ${ns} фаза ${phase}"
  fi
}

check_cluster_nodes() {
  local nodes_json total_count ready_count not_ready_count
  nodes_json="$(kubectl get nodes -o json 2>/dev/null || true)"
  if [[ -z "${nodes_json}" ]]; then
    fail "Не удалось получить список node"
    return
  fi

  total_count="$(printf '%s' "${nodes_json}" | jq '[.items[]] | length')"
  ready_count="$(
    printf '%s' "${nodes_json}" \
      | jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length'
  )"
  not_ready_count=$((total_count - ready_count))

  printf '[CHECK] nodes ready=%s/%s\n' "${ready_count}" "${total_count}"

  if (( ready_count == 0 )); then
    fail "В кластере нет Ready node"
    kubectl get nodes -o wide || true
    return
  fi

  if (( not_ready_count > 0 )); then
    if [[ "${NODE_READINESS_WARN_ONLY}" == "true" ]]; then
      warn "Найдено ${not_ready_count} node(s) не в Ready"
    else
      fail "Найдено ${not_ready_count} node(s) не в Ready"
    fi
    kubectl get nodes -o wide || true
  fi
}

check_app() {
  local app="$1"
  local allow_outofsync="${2:-false}"
  local app_json sync_status health_status

  app_json="$(kubectl -n "${ARGOCD_NS}" get application "${app}" -o json 2>/dev/null || true)"
  if [[ -z "${app_json}" ]]; then
    fail "Отсутствует Argo app: ${app}"
    return
  fi

  sync_status="$(printf '%s' "${app_json}" | jq -r '.status.sync.status // "Unknown"')"
  health_status="$(printf '%s' "${app_json}" | jq -r '.status.health.status // "Unknown"')"
  printf '[CHECK] app=%s sync=%s health=%s\n' "${app}" "${sync_status}" "${health_status}"

  if [[ "${sync_status}" != "Synced" ]]; then
    if [[ "${allow_outofsync}" == "true" && "${sync_status}" == "OutOfSync" && "${health_status}" == "Healthy" ]]; then
      warn "App ${app} в состоянии OutOfSync, но Healthy (допустимо в текущем режиме)"
    else
      fail "У app ${app} sync status=${sync_status}"
    fi
  fi
  [[ "${health_status}" == "Healthy" ]] || fail "У app ${app} health status=${health_status}"
}

diagnose_monitoring_scheduling() {
  local pod_json pending_pods
  pod_json="$(kubectl -n monitoring get pods -o json 2>/dev/null || true)"
  [[ -n "${pod_json}" ]] || return 0

  pending_pods="$(
    printf '%s' "${pod_json}" \
      | jq -r '.items[] | select(.status.phase == "Pending") | .metadata.name'
  )"

  [[ -n "${pending_pods}" ]] || return 0

  while IFS= read -r pod; do
    [[ -n "${pod}" ]] || continue
    local schedule_message
    schedule_message="$(
      kubectl -n monitoring get pod "${pod}" -o json 2>/dev/null \
        | jq -r '.status.conditions[]? | select(.type == "PodScheduled") | .message // empty'
    )"
    if [[ -n "${schedule_message}" ]]; then
      warn "Pod monitoring/${pod} не расписан: ${schedule_message}"
    fi
  done <<< "${pending_pods}"

  local failed_scheduling
  failed_scheduling="$(
    kubectl -n monitoring get events \
      --field-selector=reason=FailedScheduling,type=Warning \
      --sort-by=.lastTimestamp 2>/dev/null \
      | tail -n 10
  )"
  if [[ -n "${failed_scheduling}" ]]; then
    warn "Последние FailedScheduling events в monitoring:"
    printf '%s\n' "${failed_scheduling}"
  fi
}

check_vault_runtime() {
  if ! kubectl -n "${VAULT_NS}" get pod "${VAULT_POD}" >/dev/null 2>&1; then
    fail "Отсутствует Vault pod: ${VAULT_NS}/${VAULT_POD}"
    return
  fi

  local status_json rc
  set +e
  status_json="$(kubectl -n "${VAULT_NS}" exec "${VAULT_POD}" -- vault status -format=json 2>/dev/null)"
  rc=$?
  set -e
  if [[ ${rc} -ne 0 && ${rc} -ne 2 ]]; then
    fail "Команда vault status завершилась ошибкой для ${VAULT_NS}/${VAULT_POD}"
    return
  fi

  local initialized sealed
  initialized="$(printf '%s' "${status_json}" | jq -r '.initialized')"
  sealed="$(printf '%s' "${status_json}" | jq -r '.sealed')"
  printf '[CHECK] vault initialized=%s sealed=%s\n' "${initialized}" "${sealed}"
  [[ "${initialized}" == "true" ]] || fail "Vault не инициализирован"
  [[ "${sealed}" == "false" ]] || fail "Vault запечатан (sealed)"
}

check_monitoring_pods() {
  local bad_count
  bad_count="$(kubectl -n monitoring get pods -o json 2>/dev/null \
    | jq '[.items[] | select((.status.phase != "Running") and (.status.phase != "Succeeded"))] | length' \
    || echo "0")"
  [[ "${bad_count}" =~ ^[0-9]+$ ]] || bad_count=0
  if (( bad_count > 0 )); then
    warn "Найдено ${bad_count} pod(ов) monitoring не в статусе Running/Succeeded"
    kubectl -n monitoring get pods --no-headers || true
    diagnose_monitoring_scheduling
  fi
}

main() {
  require_tools

  local vault_profile obs_profile obs_stack
  local obs_values="${INFRA_REPO_DIR}/observability/values.yaml"
  local vault_values="${INFRA_REPO_DIR}/vault/values.yaml"
  vault_profile="$(read_value "${vault_values}" "profile" || true)"
  obs_profile="$(read_value "${obs_values}" "profile" || true)"
  obs_stack="$(read_value "${obs_values}" "observabilityStack" || true)"
  [[ -n "${obs_stack}" ]] || obs_stack="vm-loki-grafana"

  info "Обнаружены профили: vault=${vault_profile:-unknown}, observability=${obs_profile:-unknown}, stack=${obs_stack}"

  check_cluster_nodes
  check_namespace vault
  check_namespace monitoring

  check_app infrastructure-vault
  check_app infrastructure-observability
  if [[ "${vault_profile}" == "test" && "${ALLOW_VAULT_OUTOFSYNC_IN_TEST}" == "true" ]]; then
    check_app vault true
  else
    check_app vault
  fi

  local app
  while IFS= read -r app; do
    [[ -n "${app}" ]] || continue
    check_app "${app}"
  done < <(render_observability_apps)

  check_vault_runtime
  check_monitoring_pods

  if (( errors > 0 )); then
    printf '\n[RESULT] FAILED: %d error(s), %d warning(s)\n' "${errors}" "${warnings}" >&2
    exit 1
  fi

  printf '\n[RESULT] OK: %d warning(s)\n' "${warnings}"
}

main "$@"
