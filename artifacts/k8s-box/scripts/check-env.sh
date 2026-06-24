#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-${ROOT_DIR}/.env}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

is_placeholder() {
  local v="${1:-}"
  [[ -z "${v}" ]] && return 0
  [[ "${v}" == *"CHANGE_ME"* ]] && return 0
  [[ "${v}" == "<"*">" ]] && return 0
  [[ "${v}" == "string" ]] && return 0
  return 1
}

require_var() {
  local name="$1"
  local value="${!name:-}"
  if is_placeholder "${value}"; then
    err "Переменная '${name}' пустая или содержит плейсхолдер"
    return 1
  fi
  return 0
}

validate_enum_var() {
  local name="$1"
  local value="${!name:-}"
  shift
  local allowed

  if [[ -z "${value}" ]]; then
    return 0
  fi

  for allowed in "$@"; do
    if [[ "${value}" == "${allowed}" ]]; then
      return 0
    fi
  done

  err "Переменная '${name}' имеет недопустимое значение '${value}'. Допустимо: $*"
  return 1
}

validate_bool_var() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "${value}" ]]; then
    return 0
  fi

  case "${value}" in
    true|false) return 0 ;;
  esac

  err "Переменная '${name}' должна быть true или false, сейчас: '${value}'"
  return 1
}

if [[ ! -f "${ENV_FILE}" ]]; then
  err "Файл env не найден: ${ENV_FILE}"
  err "Создай его из шаблона: cp ${ROOT_DIR}/.env.example ${ROOT_DIR}/.env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

issues=0

# Yandex-токен: хотя бы один из них должен быть валидным
if is_placeholder "${TF_VAR_YC_TOKEN:-}" && is_placeholder "${TF_VAR_yc_token:-}" && is_placeholder "${YC_TOKEN:-}"; then
  err "Задай один из: TF_VAR_YC_TOKEN / TF_VAR_yc_token / YC_TOKEN"
  issues=1
fi

if ! is_placeholder "${TF_VAR_YC_TOKEN:-}" && ! is_placeholder "${TF_VAR_yc_token:-}" && [[ "${TF_VAR_YC_TOKEN}" != "${TF_VAR_yc_token}" ]]; then
  err "TF_VAR_YC_TOKEN и TF_VAR_yc_token различаются. Это частая shell-ловушка со старым токеном; обнови токен через ./scripts/refresh-yc-token.sh"
  issues=1
fi

if ! is_placeholder "${YC_TOKEN:-}" && ! is_placeholder "${TF_VAR_YC_TOKEN:-}" && [[ "${YC_TOKEN}" != "${TF_VAR_YC_TOKEN}" ]]; then
  err "YC_TOKEN и TF_VAR_YC_TOKEN различаются. Приведи bootstrap-токены к одному значению через ./scripts/refresh-yc-token.sh"
  issues=1
fi

# Авторизация ArgoCD + Git-репозитория
require_var "K8S_BOX_GITLAB_API_URL" || issues=1
require_var "K8S_BOX_GITLAB_GROUP_PATH" || issues=1
require_var "K8S_BOX_GITLAB_SUBGROUP" || issues=1
require_var "K8S_BOX_STATIC_GIT_REPO_BASE_URL" || issues=1
require_var "K8S_BOX_GITLAB_REPO_USER" || issues=1
require_var "ARGOCD_ADMIN_PASSWORD" || issues=1

if is_placeholder "${K8S_BOX_GITLAB_REPO_TOKEN:-}" && is_placeholder "${GITLAB_TOKEN:-}"; then
  err "Задай K8S_BOX_GITLAB_REPO_TOKEN или GITLAB_TOKEN"
  issues=1
fi

validate_enum_var "K8S_BOX_CLUSTER_PROFILE" test dev prod || issues=1
validate_enum_var "K8S_BOX_OBSERVABILITY_STACK" vm-loki-grafana prom-loki-grafana || issues=1
validate_enum_var "K8S_BOX_OBSERVABILITY_PROFILE" test dev prod || issues=1
validate_enum_var "K8S_BOX_OBSERVABILITY_SECRET_PROVIDER" vso external-secrets manual || issues=1
validate_bool_var "K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST" || issues=1
validate_enum_var "K8S_BOX_VAULT_PROFILE" test prod || issues=1
validate_bool_var "K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS" || issues=1
validate_bool_var "K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST" || issues=1
validate_bool_var "K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS" || issues=1
validate_bool_var "K8S_BOX_ENABLE_NLB_HC_RULE" || issues=1

if [[ "${issues}" -ne 0 ]]; then
  err "Проверка env завершилась с ошибками"
  exit 1
fi

info "Проверка env пройдена: ${ENV_FILE}"
