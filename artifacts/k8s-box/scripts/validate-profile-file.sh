#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${1:-}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

validate_enum() {
  local name="$1"
  local value="${!name:-}"
  shift
  local allowed

  [[ -n "${value}" ]] || { err "Переменная '${name}' пустая"; return 1; }

  for allowed in "$@"; do
    [[ "${value}" == "${allowed}" ]] && return 0
  done

  err "Переменная '${name}' имеет недопустимое значение '${value}'. Допустимо: $*"
  return 1
}

validate_bool() {
  local name="$1"
  local value="${!name:-}"
  case "${value}" in
    true|false) return 0 ;;
    *) err "Переменная '${name}' должна быть true или false, сейчас: '${value}'"; return 1 ;;
  esac
}

validate_int() {
  local name="$1"
  local value="${!name:-}"
  [[ "${value}" =~ ^[0-9]+$ ]] || { err "Переменная '${name}' должна быть целым числом, сейчас: '${value}'"; return 1; }
  return 0
}

[[ -n "${PROFILE_FILE}" ]] || {
  err "Использование: ./scripts/validate-profile-file.sh <profiles/*.env>"
  exit 1
}

[[ -f "${PROFILE_FILE}" ]] || {
  err "Файл профиля не найден: ${PROFILE_FILE}"
  exit 1
}

set -a
# shellcheck disable=SC1090
source "${PROFILE_FILE}"
set +a

issues=0

validate_enum "K8S_BOX_CLUSTER_PROFILE" test dev prod || issues=1
validate_enum "K8S_BOX_DEPLOYMENT_ENV" test dev prod || issues=1
validate_enum "K8S_BOX_RELEASE_CHANNEL" RAPID REGULAR STABLE || issues=1
validate_enum "K8S_BOX_CNI_TYPE" calico cilium || issues=1
validate_enum "K8S_BOX_VAULT_PROFILE" test prod || issues=1
validate_enum "K8S_BOX_OBSERVABILITY_STACK" vm-loki-grafana prom-loki-grafana || issues=1
validate_enum "K8S_BOX_OBSERVABILITY_PROFILE" test dev prod || issues=1
validate_enum "K8S_BOX_OBSERVABILITY_SECRET_PROVIDER" vso external-secrets manual || issues=1

validate_bool "K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS" || issues=1
validate_bool "K8S_BOX_MASTER_PUBLIC_ACCESS" || issues=1
validate_bool "K8S_BOX_ENABLE_NLB_HC_RULE" || issues=1
validate_bool "K8S_BOX_MONITORING_ENABLED" || issues=1
validate_bool "K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS" || issues=1
validate_bool "K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST" || issues=1
validate_bool "K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST" || issues=1

validate_int "K8S_BOX_NODE_CORES" || issues=1
validate_int "K8S_BOX_NODE_MEMORY_GB" || issues=1
validate_int "K8S_BOX_NODE_BOOT_DISK_GB" || issues=1
validate_int "K8S_BOX_WORKER_MIN" || issues=1
validate_int "K8S_BOX_WORKER_MAX" || issues=1
validate_int "K8S_BOX_WORKER_INITIAL" || issues=1

if [[ "${issues}" -ne 0 ]]; then
  err "Проверка профиля завершилась с ошибками"
  exit 1
fi

if (( K8S_BOX_WORKER_MIN < 1 )); then
  err "K8S_BOX_WORKER_MIN должен быть >= 1"
  issues=1
fi
if (( K8S_BOX_WORKER_MAX < K8S_BOX_WORKER_MIN )); then
  err "K8S_BOX_WORKER_MAX должен быть >= K8S_BOX_WORKER_MIN"
  issues=1
fi
if (( K8S_BOX_WORKER_INITIAL < K8S_BOX_WORKER_MIN || K8S_BOX_WORKER_INITIAL > K8S_BOX_WORKER_MAX )); then
  err "K8S_BOX_WORKER_INITIAL должен быть в диапазоне [K8S_BOX_WORKER_MIN..K8S_BOX_WORKER_MAX]"
  issues=1
fi

if [[ "${issues}" -ne 0 ]]; then
  err "Проверка профиля завершилась с ошибками"
  exit 1
fi

if [[ "${K8S_BOX_CLUSTER_PROFILE}" == "test" ]]; then
  [[ "${K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS}" == "false" ]] || warn "Для test рекомендуется K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS=false"
  [[ "${K8S_BOX_ENABLE_NLB_HC_RULE}" == "false" ]] || warn "Для test рекомендуется K8S_BOX_ENABLE_NLB_HC_RULE=false"
  [[ "${K8S_BOX_MONITORING_ENABLED}" == "false" ]] || warn "Для test monitoring-node group обычно не нужна"
fi

if [[ "${K8S_BOX_CLUSTER_PROFILE}" == "prod" ]]; then
  (( K8S_BOX_WORKER_MIN >= 2 )) || warn "Для prod рекомендуется K8S_BOX_WORKER_MIN >= 2"
  [[ "${K8S_BOX_MONITORING_ENABLED}" == "true" ]] || warn "Для prod рекомендуется K8S_BOX_MONITORING_ENABLED=true"
  [[ "${K8S_BOX_VAULT_PROFILE}" == "prod" ]] || warn "Для prod рекомендуется K8S_BOX_VAULT_PROFILE=prod"
fi

printf '[INFO] Профиль валиден: %s\n' "${PROFILE_FILE}"
printf '[INFO] profile=%s cluster=%s version=%s stack=%s vault=%s\n' \
  "${K8S_BOX_CLUSTER_PROFILE}" \
  "${K8S_BOX_CLUSTER_NAME:-unknown}" \
  "${K8S_BOX_CLUSTER_VERSION:-unknown}" \
  "${K8S_BOX_OBSERVABILITY_STACK}" \
  "${K8S_BOX_VAULT_PROFILE}"
