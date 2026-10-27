#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
NAMESPACE_DELETE_TIMEOUT_SEC="${NAMESPACE_DELETE_TIMEOUT_SEC:-120}"
FORCE_FINALIZE_NAMESPACES="${FORCE_FINALIZE_NAMESPACES:-false}"
DELETE_NAMESPACES="${DELETE_NAMESPACES:-false}"
AUTO_BOOTSTRAP_VAULT_TEST="${AUTO_BOOTSTRAP_VAULT_TEST:-true}"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${SCRIPT_DIR}/../../infrastructure}"
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-600}"
RUN_HEALTHCHECK_AFTER_REDEPLOY="${RUN_HEALTHCHECK_AFTER_REDEPLOY:-true}"
ALLOW_VAULT_OUTOFSYNC_IN_TEST="${ALLOW_VAULT_OUTOFSYNC_IN_TEST:-true}"

PARENT_APPS=(
  infrastructure-vault
  infrastructure-observability
)

CHILD_APPS=()
EXPECTED_CHILD_APPS=()
TARGET_NAMESPACES=()

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

require_tools() {
  command -v kubectl >/dev/null 2>&1 || { warn "Не найден kubectl"; exit 1; }
  command -v jq >/dev/null 2>&1 || { warn "Не найден jq"; exit 1; }

  local kube_context
  kube_context="$(kubectl config current-context 2>/dev/null || true)"
  [[ -n "${kube_context}" ]] || { warn "Не настроен kubectl context"; exit 1; }
}

render_observability_apps() {
  if ! command -v helm >/dev/null 2>&1; then
    return 1
  fi

  local chart_dir="${INFRA_REPO_DIR}/observability"
  [[ -d "${chart_dir}" ]] || return 1

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

read_profile() {
  local values_file="$1"
  [[ -f "${values_file}" ]] || return 1
  grep -E '^[[:space:]]*profile:' "${values_file}" \
    | head -n1 \
    | awk -F ':' '{print $2}' \
    | cut -d '#' -f1 \
    | xargs
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

detect_observability_stack() {
  local obs_values="${INFRA_REPO_DIR}/observability/values.yaml"
  local stack
  stack="$(read_value "${obs_values}" "observabilityStack" || true)"
  [[ -n "${stack}" ]] || stack="vm-loki-grafana"
  printf '%s' "${stack}"
}

build_child_apps() {
  local stack="$1"

  # Удаляем объединенный набор дочерних Application.
  # Это устойчиво к переключению между VSO/ExternalSecrets/manual и смене стека.
  CHILD_APPS=(
    vault
    monitoring-loki
    monitoring-vault-secrets-operator
    monitoring-external-secrets-operator
    monitoring-alertmanager-vault-secrets
    monitoring-alertmanager-external-secrets
  )

  case "${stack}" in
    vm-loki-grafana) CHILD_APPS+=(monitoring-victoria-metrics-stack) ;;
    prom-loki-grafana) CHILD_APPS+=(monitoring-kube-prometheus-stack) ;;
    *)
      warn "Неподдерживаемый observabilityStack=${stack}; используем fallback на приложения vm-loki-grafana"
      CHILD_APPS+=(monitoring-victoria-metrics-stack)
      ;;
  esac
}

build_expected_child_apps() {
  local rendered_apps=""
  EXPECTED_CHILD_APPS=(vault)
  rendered_apps="$(render_observability_apps || true)"
  if [[ -n "${rendered_apps}" ]]; then
    mapfile -t EXPECTED_CHILD_APPS < <(
      {
        printf '%s\n' "vault"
        printf '%s\n' "${rendered_apps}"
      } | awk 'NF'
    )
    return 0
  fi

  local app
  for app in "${CHILD_APPS[@]}"; do
    if kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1; then
      case " ${EXPECTED_CHILD_APPS[*]} " in
        *" ${app} "*) ;;
        *) EXPECTED_CHILD_APPS+=("${app}") ;;
      esac
    fi
  done
}

build_target_namespaces() {
  TARGET_NAMESPACES=(
    vault
    monitoring
    external-secrets
    vault-secrets-operator-system
  )
}

wait_for_app() {
  local app="$1"
  for _ in $(seq 1 60); do
    if kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

trigger_app_sync() {
  local app="$1"
  kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1 || return 0
  kubectl -n "${ARGOCD_NS}" annotate application "${app}" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  kubectl -n "${ARGOCD_NS}" patch application "${app}" --type merge \
    -p '{"operation":{"sync":{"prune":true,"syncOptions":["CreateNamespace=true"]}}}' >/dev/null
}

app_ready() {
  local app="$1"
  local vault_profile sync_status health_status
  vault_profile="$(read_profile "${INFRA_REPO_DIR}/vault/values.yaml" || true)"

  sync_status="$(kubectl -n "${ARGOCD_NS}" get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health_status="$(kubectl -n "${ARGOCD_NS}" get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

  if [[ "${sync_status}" == "Synced" && "${health_status}" == "Healthy" ]]; then
    return 0
  fi

  if [[ "${app}" == "vault" && "${vault_profile}" == "test" && "${ALLOW_VAULT_OUTOFSYNC_IN_TEST}" == "true" ]]; then
    if [[ "${sync_status}" == "OutOfSync" && "${health_status}" == "Healthy" ]]; then
      warn "App vault is OutOfSync but Healthy (allowed in test mode)"
      return 0
    fi
  fi

  return 1
}

wait_app_ready() {
  local app="$1"
  local deadline=$((SECONDS + WAIT_TIMEOUT_SEC))

  while (( SECONDS < deadline )); do
    if ! kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1; then
      sleep 3
      continue
    fi
    if app_ready "${app}"; then
      return 0
    fi
    sleep 5
  done

  warn "App не стало готовым вовремя: ${app}"
  kubectl -n "${ARGOCD_NS}" get application "${app}" \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers \
    || true
  return 1
}

wait_apps_ready() {
  local title="$1"
  shift || true
  local apps=("$@")
  [[ ${#apps[@]} -gt 0 ]] || return 0

  info "Ждем готовности ${title}"
  local app
  for app in "${apps[@]}"; do
    wait_app_ready "${app}" || return 1
  done
}

resync_nonready_apps_once() {
  local apps=("$@")
  [[ ${#apps[@]} -gt 0 ]] || return 0

  local retry_apps=()
  local app
  for app in "${apps[@]}"; do
    if ! kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1; then
      continue
    fi
    if ! app_ready "${app}"; then
      retry_apps+=("${app}")
    fi
  done

  [[ ${#retry_apps[@]} -gt 0 ]] || return 0

  info "Повторно синхронизируем app, которые не вышли в ready: ${retry_apps[*]}"
  for app in "${retry_apps[@]}"; do
    trigger_app_sync "${app}"
  done
  sleep 5
  wait_apps_ready "app после повторного sync" "${retry_apps[@]}"
}

wait_for_namespace_deletion() {
  local ns="$1"
  local deadline=$((SECONDS + NAMESPACE_DELETE_TIMEOUT_SEC))

  while (( SECONDS < deadline )); do
    if ! kubectl get namespace "${ns}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

force_finalize_namespace() {
  local ns="$1"
  info "Namespace ${ns} все еще существует, принудительно очищаем finalizer"
  kubectl get namespace "${ns}" -o json \
    | jq '.spec.finalizers=[]' \
    | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - >/dev/null
}

delete_phase() {
  info "Удаляем дочерние приложения"
  kubectl -n "${ARGOCD_NS}" delete application "${CHILD_APPS[@]}" --ignore-not-found --wait=false >/dev/null || true

  info "Удаляем родительские приложения"
  kubectl -n "${ARGOCD_NS}" delete application "${PARENT_APPS[@]}" --ignore-not-found --wait=false >/dev/null || true

  if [[ "${DELETE_NAMESPACES}" != "true" ]]; then
    info "Пропускаем удаление namespace (DELETE_NAMESPACES=false)"
    return 0
  fi

  info "Удаляем целевые namespace"
  kubectl delete namespace "${TARGET_NAMESPACES[@]}" --ignore-not-found --wait=false >/dev/null || true

  for ns in "${TARGET_NAMESPACES[@]}"; do
    if wait_for_namespace_deletion "${ns}"; then
      continue
    fi

    warn "Namespace ${ns} не удален за ${NAMESPACE_DELETE_TIMEOUT_SEC} сек"
    if [[ "${FORCE_FINALIZE_NAMESPACES}" == "true" ]]; then
      force_finalize_namespace "${ns}"
      sleep 2
      if ! wait_for_namespace_deletion "${ns}"; then
        warn "Namespace ${ns} все еще существует после принудительной финализации"
      fi
    else
      warn "Повтори запуск с FORCE_FINALIZE_NAMESPACES=true, только если это блокирует redeploy"
    fi
  done
}

ensure_namespaces_exist() {
  for ns in "${TARGET_NAMESPACES[@]}"; do
    if kubectl get namespace "${ns}" >/dev/null 2>&1; then
      continue
    fi
    info "Создаем namespace ${ns}"
    kubectl create namespace "${ns}" >/dev/null 2>&1 || true
  done
}

sync_phase() {
  info "Ждем, пока ApplicationSet пересоздаст родительские приложения"
  for app in "${PARENT_APPS[@]}"; do
    if ! wait_for_app "${app}"; then
      warn "Родительское app не было пересоздано вовремя: ${app}"
      exit 1
    fi
    trigger_app_sync "${app}"
  done
}

recover_stuck_deployments() {
  local ns="monitoring"
  local deploy_json
  if ! deploy_json="$(kubectl -n "${ns}" get deployment -o json 2>/dev/null)"; then
    return 0
  fi

  local stuck_list
  stuck_list="$(
    printf '%s' "${deploy_json}" \
      | jq -r '.items[] | select((.spec.replicas // 0) > 0 and (.status.replicas // 0) == 0) | .metadata.name'
  )"

  if [[ -z "${stuck_list}" ]]; then
    return 0
  fi

  info "Восстанавливаем зависшие deployment в namespace ${ns}"
  while IFS= read -r deploy; do
    [[ -z "${deploy}" ]] && continue
    local desired
    desired="$(kubectl -n "${ns}" get deployment "${deploy}" -o jsonpath='{.spec.replicas}')"
    [[ -z "${desired}" ]] && desired="1"
    info "Перезапуск масштаба: ${deploy} (${desired})"
    kubectl -n "${ns}" scale deployment "${deploy}" --replicas=0 >/dev/null
    sleep 1
    kubectl -n "${ns}" scale deployment "${deploy}" --replicas="${desired}" >/dev/null
  done <<< "${stuck_list}"
}

bootstrap_vault_test_if_needed() {
  if [[ "${AUTO_BOOTSTRAP_VAULT_TEST}" != "true" ]]; then
    return 0
  fi

  local profile=""
  profile="$(read_profile "${INFRA_REPO_DIR}/vault/values.yaml" || true)"
  if [[ "${profile}" != "test" ]]; then
    return 0
  fi

  local bootstrap_script="${SCRIPT_DIR}/vault-test-bootstrap.sh"
  if [[ ! -x "${bootstrap_script}" ]]; then
    warn "Скрипт bootstrap Vault не найден или не исполняемый: ${bootstrap_script}"
    return 0
  fi

  info "Запускаем идемпотентный bootstrap Vault для test"
  "${bootstrap_script}"
}

status_phase() {
  info "Текущие приложения ArgoCD"
  kubectl -n "${ARGOCD_NS}" get applications \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers \
    | sort
  echo
  info "Целевые namespace"
  for ns in "${TARGET_NAMESPACES[@]}"; do
    if kubectl get namespace "${ns}" >/dev/null 2>&1; then
      printf '%-18s %s\n' "${ns}" "$(kubectl get namespace "${ns}" -o jsonpath='{.status.phase}')"
    else
      printf '%-18s %s\n' "${ns}" "Не найден"
    fi
  done
}

usage() {
  cat <<EOF
Использование:
  ./scripts/redeploy-gitops-apps.sh [redeploy|wipe|status]

Режимы:
  redeploy  Удалить vault/observability app (и при необходимости namespace), затем пересоздать через ApplicationSet.
  wipe      Полная очистка: redeploy c DELETE_NAMESPACES=true FORCE_FINALIZE_NAMESPACES=true.
  status    Показать текущее состояние app и namespace.

Переменные окружения:
  DELETE_NAMESPACES=true                    Также удалять namespace vault/monitoring/external-secrets
  NAMESPACE_DELETE_TIMEOUT_SEC=<seconds>   Таймаут ожидания удаления namespace (по умолчанию: 120)
  FORCE_FINALIZE_NAMESPACES=true           Принудительно чистить finalizer namespace при зависании удаления
  AUTO_BOOTSTRAP_VAULT_TEST=true           Автоматически запускать vault-test-bootstrap.sh для vault profile=test
  INFRA_REPO_DIR=<path>                    Путь к репозиторию infrastructure (по умолчанию: ../infrastructure)
  WAIT_TIMEOUT_SEC=<seconds>               Таймаут ожидания готовности app после redeploy (по умолчанию: 600)
  RUN_HEALTHCHECK_AFTER_REDEPLOY=true      После redeploy запускать healthcheck-vault-observability.sh
  ALLOW_VAULT_OUTOFSYNC_IN_TEST=true       Разрешать vault OutOfSync/Healthy в test-профиле
EOF
}

main() {
  local mode="${1:-redeploy}"
  require_tools
  build_child_apps "$(detect_observability_stack)"
  build_target_namespaces

  case "${mode}" in
    redeploy)
      delete_phase
      ensure_namespaces_exist
      sync_phase
      wait_apps_ready "родительских app" "${PARENT_APPS[@]}"
      build_expected_child_apps
      if [[ ${#EXPECTED_CHILD_APPS[@]} -gt 0 ]]; then
        local app
        for app in "${EXPECTED_CHILD_APPS[@]}"; do
          trigger_app_sync "${app}"
        done
      fi
      sleep 5
      recover_stuck_deployments
      bootstrap_vault_test_if_needed
      wait_apps_ready "дочерних app" "${EXPECTED_CHILD_APPS[@]}"
      resync_nonready_apps_once "${PARENT_APPS[@]}" "${EXPECTED_CHILD_APPS[@]}"
      recover_stuck_deployments
      if [[ "${RUN_HEALTHCHECK_AFTER_REDEPLOY}" == "true" ]]; then
        "${SCRIPT_DIR}/healthcheck-vault-observability.sh"
      fi
      sleep 5
      status_phase
      ;;
    wipe)
      DELETE_NAMESPACES=true
      FORCE_FINALIZE_NAMESPACES=true
      delete_phase
      ensure_namespaces_exist
      sync_phase
      wait_apps_ready "родительских app" "${PARENT_APPS[@]}"
      build_expected_child_apps
      if [[ ${#EXPECTED_CHILD_APPS[@]} -gt 0 ]]; then
        local app
        for app in "${EXPECTED_CHILD_APPS[@]}"; do
          trigger_app_sync "${app}"
        done
      fi
      sleep 5
      recover_stuck_deployments
      bootstrap_vault_test_if_needed
      wait_apps_ready "дочерних app" "${EXPECTED_CHILD_APPS[@]}"
      resync_nonready_apps_once "${PARENT_APPS[@]}" "${EXPECTED_CHILD_APPS[@]}"
      recover_stuck_deployments
      if [[ "${RUN_HEALTHCHECK_AFTER_REDEPLOY}" == "true" ]]; then
        "${SCRIPT_DIR}/healthcheck-vault-observability.sh"
      fi
      sleep 5
      status_phase
      ;;
    status)
      status_phase
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
