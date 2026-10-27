#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${ROOT_DIR}/../infrastructure}"
VALUES_FILE="${INFRA_REPO_DIR}/vault/values.yaml"

info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Использование:
  ./scripts/set-vault-profile.sh <test|prod> [--enable-backup-manifests <true|false>] [--enable-backup-in-test <true|false>]

Примеры:
  ./scripts/set-vault-profile.sh test
  ./scripts/set-vault-profile.sh prod --enable-backup-manifests true
  ./scripts/set-vault-profile.sh test --enable-backup-manifests true --enable-backup-in-test false

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

main() {
  [[ -f "${VALUES_FILE}" ]] || fail "Не найден values-файл: ${VALUES_FILE}"

  local profile="${1:-}"
  [[ -n "${profile}" ]] || { usage; exit 1; }
  shift || true

  case "${profile}" in
    test|prod) ;;
    *) fail "Неподдерживаемый профиль Vault: ${profile}" ;;
  esac

  local enable_backup_manifests=""
  local enable_backup_in_test=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enable-backup-manifests)
        enable_backup_manifests="${2:-}"
        shift 2
        ;;
      --enable-backup-in-test)
        enable_backup_in_test="${2:-}"
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

  if [[ -n "${enable_backup_manifests}" ]]; then
    case "${enable_backup_manifests}" in
      true|false) ;;
      *) fail "Значение --enable-backup-manifests должно быть true или false" ;;
    esac
  fi
  if [[ -n "${enable_backup_in_test}" ]]; then
    case "${enable_backup_in_test}" in
      true|false) ;;
      *) fail "Значение --enable-backup-in-test должно быть true или false" ;;
    esac
  fi

  if [[ "${KEEP_BACKUP:-false}" == "true" ]]; then
    cp "${VALUES_FILE}" "${VALUES_FILE}.bak"
  fi

  replace_or_append_key "${VALUES_FILE}" "profile" "${profile}"
  if [[ -n "${enable_backup_manifests}" ]]; then
    replace_or_append_key "${VALUES_FILE}" "enableBackupManifests" "${enable_backup_manifests}"
  fi
  if [[ -n "${enable_backup_in_test}" ]]; then
    replace_or_append_key "${VALUES_FILE}" "enableBackupManifestsInTest" "${enable_backup_in_test}"
  fi

  info "Обновлен ${VALUES_FILE}"
  info "profile=${profile}${enable_backup_manifests:+, enableBackupManifests=${enable_backup_manifests}}${enable_backup_in_test:+, enableBackupManifestsInTest=${enable_backup_in_test}}"

  if [[ -x "${INFRA_REPO_DIR}/.ci/validate-gitops.sh" ]]; then
    info "Запускаем валидацию: ${INFRA_REPO_DIR}/.ci/validate-gitops.sh"
    (cd "${INFRA_REPO_DIR}" && ./.ci/validate-gitops.sh)
  else
    info "Скрипт валидации не найден, пропускаем."
  fi
}

main "$@"
