#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${ROOT_DIR}/../infrastructure}"
VALUES_FILE="${INFRA_REPO_DIR}/observability/values.yaml"

info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Использование:
  ./scripts/set-observability-stack.sh <vm-loki-grafana|prom-loki-grafana> [--profile <test|dev|prod>] [--secret-provider <vso|external-secrets|manual>] [--enable-secret-sync-in-test <true|false>]

Примеры:
  ./scripts/set-observability-stack.sh vm-loki-grafana
  ./scripts/set-observability-stack.sh prom-loki-grafana --profile test
  ./scripts/set-observability-stack.sh vm-loki-grafana --profile prod --secret-provider vso
  ./scripts/set-observability-stack.sh prom-loki-grafana --profile test --secret-provider manual --enable-secret-sync-in-test false

Переменные окружения:
  INFRA_REPO_DIR=<path>   путь к репозиторию infrastructure (по умолчанию: ../infrastructure)
  KEEP_BACKUP=true        сохранять values.yaml.bak перед обновлением (по умолчанию: false)
EOF
}

replace_or_append_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -qE "^[[:space:]]*${key}:" "${file}"; then
    perl -0pi -e "s/^([[:space:]]*${key}:[[:space:]]*).*?([[:space:]]*#.*)?\$/\$1${value}\$2/m" "${file}"
  else
    printf '\n%s: %s\n' "${key}" "${value}" >> "${file}"
  fi
}

replace_nested_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -qE "^[[:space:]]+${key}:" "${file}"; then
    perl -0pi -e "s/^([[:space:]]+${key}:[[:space:]]*).*?([[:space:]]*#.*)?\$/\$1${value}\$2/m" "${file}"
  else
    fail "Ключ ${key} не найден в ${file}; ожидалась стандартная структура observability/values.yaml"
  fi
}

main() {
  [[ -f "${VALUES_FILE}" ]] || fail "Не найден values-файл: ${VALUES_FILE}"

  local stack="${1:-}"
  [[ -n "${stack}" ]] || { usage; exit 1; }
  shift || true

  case "${stack}" in
    vm-loki-grafana|prom-loki-grafana) ;;
    *) fail "Неподдерживаемый stack: ${stack}" ;;
  esac

  local profile=""
  local secret_provider=""
  local secret_sync_in_test=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        profile="${2:-}"
        shift 2
        ;;
      --secret-provider)
        secret_provider="${2:-}"
        shift 2
        ;;
      --enable-secret-sync-in-test)
        secret_sync_in_test="${2:-}"
        shift 2
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        fail "Неизвестный аргумент: $1"
        ;;
    esac
  done

  if [[ -n "${profile}" ]]; then
    case "${profile}" in
      test|dev|prod) ;;
      *) fail "Неподдерживаемый профиль: ${profile}" ;;
    esac
  fi
  if [[ -n "${secret_provider}" ]]; then
    case "${secret_provider}" in
      vso|external-secrets|manual) ;;
      *) fail "Неподдерживаемый secret provider: ${secret_provider}" ;;
    esac
  fi
  if [[ -n "${secret_sync_in_test}" ]]; then
    case "${secret_sync_in_test}" in
      true|false) ;;
      *) fail "Значение --enable-secret-sync-in-test должно быть true или false" ;;
    esac
  fi

  if [[ "${KEEP_BACKUP:-false}" == "true" ]]; then
    cp "${VALUES_FILE}" "${VALUES_FILE}.bak"
  fi
  replace_or_append_key "${VALUES_FILE}" "observabilityStack" "${stack}"
  if [[ -n "${profile}" ]]; then
    replace_or_append_key "${VALUES_FILE}" "profile" "${profile}"
  fi
  if [[ -n "${secret_provider}" ]]; then
    replace_nested_key "${VALUES_FILE}" "secretProvider" "${secret_provider}"
  fi
  if [[ -n "${secret_sync_in_test}" ]]; then
    replace_nested_key "${VALUES_FILE}" "enableSecretSyncInTest" "${secret_sync_in_test}"
  fi

  info "Обновлен ${VALUES_FILE}"
  info "observabilityStack=${stack}${profile:+, profile=${profile}}${secret_provider:+, secretProvider=${secret_provider}}${secret_sync_in_test:+, enableSecretSyncInTest=${secret_sync_in_test}}"

  if [[ -x "${INFRA_REPO_DIR}/.ci/validate-gitops.sh" ]]; then
    info "Запускаем валидацию: ${INFRA_REPO_DIR}/.ci/validate-gitops.sh"
    (cd "${INFRA_REPO_DIR}" && ./.ci/validate-gitops.sh)
  else
    info "Скрипт валидации не найден, пропускаем."
  fi
}

main "$@"
