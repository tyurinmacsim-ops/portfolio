#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOLDER_DIR="${ROOT_DIR}/folder"
ENV_HCL="${ROOT_DIR}/env.hcl"
ADDR='yandex_resourcemanager_folder.folders["k8s-box"]'
LOAD_DOTENV="${LOAD_DOTENV:-true}"
AUTO_REFRESH_YC_TOKEN="${AUTO_REFRESH_YC_TOKEN:-true}"
RUN_PLAN_AFTER_REPAIR="false"
TOKEN_WAS_GENERATED="false"
PRE_TOKEN="${TF_VAR_YC_TOKEN:-${TF_VAR_yc_token:-${YC_TOKEN:-}}}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Использование:
  ./scripts/repair-folder-state.sh [--plan]

Опции:
  --plan  Запустить 'terragrunt plan' в модуле folder после исправления state.

Переменные окружения:
  LOAD_DOTENV=true  Подгрузить k8s-box/.env перед проверками.
  AUTO_REFRESH_YC_TOKEN=true  Попробовать обновить токен через 'yc iam create-token'.
USAGE
}

hcl_string() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ "^" key "[[:space:]]*=[[:space:]]*\"") {
        sub("^" key "[[:space:]]*=[[:space:]]*\"", "", line)
        sub(/\".*/, "", line)
        print line
        exit
      }
    }
  ' "$file"
}

load_local_env() {
  local env_file="${ROOT_DIR}/.env"
  if [[ "${LOAD_DOTENV}" != "true" ]]; then
    return 0
  fi
  if [[ ! -f "${env_file}" ]]; then
    return 0
  fi

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}

ensure_yc_token_for_plan() {
  if [[ "${AUTO_REFRESH_YC_TOKEN}" == "true" ]]; then
    local fresh_token
    fresh_token="$(yc iam create-token 2>/dev/null || true)"
    if [[ -n "${fresh_token}" ]]; then
      export TF_VAR_YC_TOKEN="${fresh_token}"
      export TF_VAR_yc_token="${fresh_token}"
      TOKEN_WAS_GENERATED="true"
      info "Используем свежий YC-токен из 'yc iam create-token'"
      return 0
    fi
    warn "Не удалось обновить токен через yc, пробуем существующий TF_VAR_YC_TOKEN/YC_TOKEN"
  fi

  if [[ -n "${TF_VAR_YC_TOKEN:-}" && -z "${TF_VAR_yc_token:-}" ]]; then
    export TF_VAR_yc_token="${TF_VAR_YC_TOKEN}"
  fi
  if [[ -n "${TF_VAR_yc_token:-}" && -z "${TF_VAR_YC_TOKEN:-}" ]]; then
    export TF_VAR_YC_TOKEN="${TF_VAR_yc_token}"
  fi
  if [[ -n "${YC_TOKEN:-}" && -z "${TF_VAR_YC_TOKEN:-}" ]]; then
    export TF_VAR_YC_TOKEN="${YC_TOKEN}"
    export TF_VAR_yc_token="${YC_TOKEN}"
  fi

  if [[ -n "${TF_VAR_YC_TOKEN:-}" ]]; then
    info "Используем YC-токен из окружения"
    return 0
  fi

  local generated
  generated="$(yc iam create-token 2>/dev/null || true)"
  if [[ -n "${generated}" ]]; then
    export TF_VAR_YC_TOKEN="${generated}"
    export TF_VAR_yc_token="${generated}"
    TOKEN_WAS_GENERATED="true"
    info "Используем свежий YC-токен для текущего запуска скрипта"
    return 0
  fi

  if [[ "${RUN_PLAN_AFTER_REPAIR}" == "true" ]]; then
    fail "Для terragrunt plan нужен токен. Задай TF_VAR_YC_TOKEN (или YC_TOKEN) и повтори."
  fi

  warn "Токен не задан. Исправление завершено, но ручной terragrunt plan может завершиться ошибкой."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) RUN_PLAN_AFTER_REPAIR="true" ;;
    -h|--help|help) usage; exit 0 ;;
    *) fail "Неизвестный аргумент: $1" ;;
  esac
  shift
done

command -v terragrunt >/dev/null 2>&1 || fail "Требуется terragrunt"
command -v yc >/dev/null 2>&1 || fail "Требуется yc"
[[ -f "${ENV_HCL}" ]] || fail "Не найден env.hcl"

load_local_env

ensure_yc_token_for_plan

CLOUD_ID="$(hcl_string "${ENV_HCL}" "cloud_id")"
FOLDER_NAME="$(hcl_string "${ENV_HCL}" "folder_name")"
[[ -n "${CLOUD_ID}" ]] || fail "В env.hcl пустой cloud_id"
[[ -n "${FOLDER_NAME}" ]] || fail "В env.hcl пустой folder_name"

cd "${FOLDER_DIR}"

if ! terragrunt state list 2>/dev/null | grep -Fxq "${ADDR}"; then
  info "Ресурс folder отсутствует в state, исправлять нечего"
else
  STATE_ID="$(terragrunt state show "${ADDR}" 2>/dev/null | awk -F' = ' '/^[[:space:]]*id[[:space:]]*=/ {gsub(/"/, "", $2); print $2; exit}')"
  if [[ -z "${STATE_ID}" ]]; then
    warn "Не удалось извлечь folder id из state; удаляем устаревший адрес"
    terragrunt --non-interactive state rm "${ADDR}"
  else
    if yc resource-manager folder get --id "${STATE_ID}" --format json >/dev/null 2>&1; then
      info "ID из state '${STATE_ID}' существует в облаке, исправлять нечего"
    else
      warn "ID из state '${STATE_ID}' не найден в облаке, удаляем устаревшую запись"
      terragrunt --non-interactive state rm "${ADDR}"
    fi
  fi
fi

EXISTING_ID="$(yc --cloud-id "${CLOUD_ID}" resource-manager folder get --name "${FOLDER_NAME}" --format json --jq '.id' 2>/dev/null || true)"
if [[ -n "${EXISTING_ID}" ]]; then
  if ! terragrunt state list 2>/dev/null | grep -Fxq "${ADDR}"; then
    info "Импортируем существующий folder '${FOLDER_NAME}' (id=${EXISTING_ID}) в state"
    terragrunt --non-interactive import "${ADDR}" "${EXISTING_ID}"
  fi
else
  info "Folder '${FOLDER_NAME}' не найден в облаке, следующий plan предложит создание"
fi

if [[ "${RUN_PLAN_AFTER_REPAIR}" == "true" ]]; then
  info "Запускаем terragrunt plan в модуле folder"
  terragrunt --non-interactive plan
else
  if [[ "${TOKEN_WAS_GENERATED}" == "true" && -z "${PRE_TOKEN}" ]]; then
    warn "Токен был сгенерирован только для процесса этого скрипта."
    warn "Для ручного plan в следующей команде сначала экспортируй токен в текущий shell:"
    warn "export TF_VAR_YC_TOKEN=\"$(yc iam create-token)\""
    warn "export TF_VAR_yc_token=\"$TF_VAR_YC_TOKEN\""
  fi
  info "Исправление state завершено"
fi
