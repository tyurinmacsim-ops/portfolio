#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${ROOT_DIR}/../infrastructure}"

APPLY_RUNTIME_PROFILE="${APPLY_RUNTIME_PROFILE:-true}"
K8S_BOX_VAULT_PROFILE="${K8S_BOX_VAULT_PROFILE:-test}"
K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS="${K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS:-true}"
K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST="${K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST:-false}"
K8S_BOX_OBSERVABILITY_STACK="${K8S_BOX_OBSERVABILITY_STACK:-vm-loki-grafana}"
K8S_BOX_OBSERVABILITY_PROFILE="${K8S_BOX_OBSERVABILITY_PROFILE:-test}"
K8S_BOX_OBSERVABILITY_SECRET_PROVIDER="${K8S_BOX_OBSERVABILITY_SECRET_PROVIDER:-vso}"
K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST="${K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST:-false}"

info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Использование:
  ./scripts/apply-platform-runtime-profile.sh

Скрипт берет runtime-переключатели из env и синхронно применяет их
в соседний GitOps-репозиторий infrastructure.

Поддерживаемые env-переменные:
  K8S_BOX_VAULT_PROFILE=test|prod
  K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS=true|false
  K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST=true|false
  K8S_BOX_OBSERVABILITY_STACK=vm-loki-grafana|prom-loki-grafana
  K8S_BOX_OBSERVABILITY_PROFILE=test|dev|prod
  K8S_BOX_OBSERVABILITY_SECRET_PROVIDER=vso|external-secrets|manual
  K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST=true|false
  APPLY_RUNTIME_PROFILE=true|false
EOF
}

resolve_infra_repo_dir() {
  local explicit_dir="${INFRA_REPO_DIR:-}"
  local local_dir="${ROOT_DIR}/../infrastructure"
  local ci_dir="${ROOT_DIR}/.deps/infrastructure"

  if [[ -n "${explicit_dir}" ]]; then
    printf '%s' "${explicit_dir}"
    return 0
  fi

  if [[ -d "${local_dir}/.git" ]]; then
    printf '%s' "${local_dir}"
    return 0
  fi

  printf '%s' "${ci_dir}"
}

validate_enum() {
  local value="$1"
  shift
  local allowed
  for allowed in "$@"; do
    [[ "${value}" == "${allowed}" ]] && return 0
  done
  fail "Недопустимое значение: ${value}; допустимые: $*"
}

validate_bool() {
  case "$1" in
    true|false) ;;
    *) fail "Ожидалось true|false, получено: $1" ;;
  esac
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    usage
    exit 0
  fi

  if [[ "${APPLY_RUNTIME_PROFILE}" != "true" ]]; then
    info "APPLY_RUNTIME_PROFILE=false, пропускаем синхронизацию runtime-профиля"
    exit 0
  fi

  validate_enum "${K8S_BOX_VAULT_PROFILE}" test prod
  validate_bool "${K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS}"
  validate_bool "${K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST}"
  validate_enum "${K8S_BOX_OBSERVABILITY_STACK}" vm-loki-grafana prom-loki-grafana
  validate_enum "${K8S_BOX_OBSERVABILITY_PROFILE}" test dev prod
  validate_enum "${K8S_BOX_OBSERVABILITY_SECRET_PROVIDER}" vso external-secrets manual
  validate_bool "${K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST}"

  INFRA_REPO_DIR="$(resolve_infra_repo_dir)"
  [[ -d "${INFRA_REPO_DIR}" ]] || "${SCRIPT_DIR}/ensure-infra-repo.sh"
  INFRA_REPO_DIR="$(resolve_infra_repo_dir)"
  [[ -f "${INFRA_REPO_DIR}/vault/values.yaml" ]] || fail "Не найден INFRA_REPO_DIR=${INFRA_REPO_DIR}"

  info "Применяем runtime-профиль Vault"
  INFRA_REPO_DIR="${INFRA_REPO_DIR}" "${SCRIPT_DIR}/set-vault-profile.sh" \
    "${K8S_BOX_VAULT_PROFILE}" \
    --enable-backup-manifests "${K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS}" \
    --enable-backup-in-test "${K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST}"

  info "Применяем runtime-профиль Observability"
  INFRA_REPO_DIR="${INFRA_REPO_DIR}" "${SCRIPT_DIR}/set-observability-stack.sh" \
    "${K8S_BOX_OBSERVABILITY_STACK}" \
    --profile "${K8S_BOX_OBSERVABILITY_PROFILE}" \
    --secret-provider "${K8S_BOX_OBSERVABILITY_SECRET_PROVIDER}" \
    --enable-secret-sync-in-test "${K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST}"

  info "Runtime-профиль платформы синхронизирован"
}

main "$@"
