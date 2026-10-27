#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMEOUT_SECONDS="${K8S_BOX_YC_IAM_SMOKE_TIMEOUT_SECONDS:-45}"
TEST_ROLE="${K8S_BOX_YC_IAM_SMOKE_ROLE:-viewer}"
SMOKE_NAME_PREFIX="${K8S_BOX_YC_IAM_SMOKE_PREFIX:-k8s-box-iam-smoke}"
FOLDER_ID="${YC_FOLDER_ID:-${K8S_BOX_FOLDER_ID:-}}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

extract_op_id() {
  awk '/^id:/{print $2; exit}'
}

bootstrap_hcl_string() {
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

resolve_folder_id() {
  local bootstrap_env="${REPO_ROOT}/.generated/bootstrap-context.env"
  local env_hcl="${REPO_ROOT}/env.hcl"
  local cloud_id="${YC_CLOUD_ID:-}"
  local folder_name="${YC_FOLDER_NAME:-}"

  if [[ -n "${FOLDER_ID}" ]]; then
    printf '%s' "${FOLDER_ID}"
    return 0
  fi

  if [[ -f "${bootstrap_env}" ]]; then
    # shellcheck disable=SC1090
    source "${bootstrap_env}"
    cloud_id="${cloud_id:-${CLOUD_ID:-}}"
    folder_name="${folder_name:-${FOLDER_NAME:-}}"
  fi

  if [[ -z "${cloud_id}" && -f "${env_hcl}" ]]; then
    cloud_id="$(bootstrap_hcl_string "${env_hcl}" "cloud_id")"
  fi
  if [[ -z "${folder_name}" && -f "${env_hcl}" ]]; then
    folder_name="$(bootstrap_hcl_string "${env_hcl}" "folder_name")"
  fi

  if [[ -z "${cloud_id}" || -z "${folder_name}" ]]; then
    return 1
  fi

  YC_TOKEN="${YC_TOKEN:-}" yc resource-manager folder list \
    --cloud-id "${cloud_id}" \
    --format json \
    | jq -r --arg folder_name "${folder_name}" '.[] | select(.name == $folder_name) | select(.status == "ACTIVE") | .id' \
    | head -n1
}

resolve_yc_token() {
  if [[ -n "${TF_VAR_YC_TOKEN:-}" ]]; then
    printf '%s' "${TF_VAR_YC_TOKEN}"
    return 0
  fi
  if [[ -n "${TF_VAR_yc_token:-}" ]]; then
    printf '%s' "${TF_VAR_yc_token}"
    return 0
  fi
  if [[ -n "${YC_TOKEN:-}" ]]; then
    printf '%s' "${YC_TOKEN}"
    return 0
  fi
  yc iam create-token
}

poll_operation() {
  local op_id="$1"
  local timeout="$2"
  local started_at now op_json done

  started_at="$(date +%s)"
  while true; do
    op_json="$(YC_TOKEN="${YC_TOKEN}" yc operation get "${op_id}" --format json)"
    done="$(printf '%s' "${op_json}" | jq -r '.done // false')"

    if [[ "${done}" == "true" ]]; then
      printf '%s' "${op_json}"
      return 0
    fi

    now="$(date +%s)"
    if (( now - started_at >= timeout )); then
      printf '%s' "${op_json}"
      return 1
    fi

    sleep 5
  done
}

require_tools() {
  command -v yc >/dev/null 2>&1 || { err "Требуется yc"; exit 1; }
  command -v jq >/dev/null 2>&1 || { err "Требуется jq"; exit 1; }
}

main() {
  local token name create_out create_op create_json sa_id add_out add_op remove_out remove_op delete_out delete_op

  require_tools

  FOLDER_ID="${FOLDER_ID:-$(resolve_folder_id || true)}"

  token="$(resolve_yc_token)"
  export YC_TOKEN="${token}"
  export TF_VAR_YC_TOKEN="${TF_VAR_YC_TOKEN:-${token}}"
  export TF_VAR_yc_token="${TF_VAR_yc_token:-${TF_VAR_YC_TOKEN}}"

  FOLDER_ID="${FOLDER_ID:-$(resolve_folder_id || true)}"

  if [[ -z "${FOLDER_ID}" ]]; then
    err "Нужен YC_FOLDER_ID или K8S_BOX_FOLDER_ID"
    exit 1
  fi

  name="${SMOKE_NAME_PREFIX}-$(date +%s)"
  info "Проверяем YC IAM API на folder ${FOLDER_ID} через временный service account ${name}"

  create_out="$(YC_TOKEN="${YC_TOKEN}" yc iam service-account create --folder-id "${FOLDER_ID}" --name "${name}" --async)"
  create_op="$(printf '%s\n' "${create_out}" | extract_op_id)"
  if [[ -z "${create_op}" ]]; then
    err "Не удалось получить operation id для create service account"
    exit 1
  fi

  info "Create service account operation: ${create_op}"
  if ! create_json="$(poll_operation "${create_op}" "${TIMEOUT_SECONDS}")"; then
    err "YC IAM create service account завис дольше ${TIMEOUT_SECONDS}s"
    warn "Проверь: yc operation get ${create_op}"
    warn "Если service account все же появился позже, очисти его вручную по имени ${name}"
    exit 2
  fi

  sa_id="$(printf '%s' "${create_json}" | jq -r '.response.id // .metadata.service_account_id // empty')"
  if [[ -z "${sa_id}" || "${sa_id}" == "null" ]]; then
    err "Не удалось определить service account id из операции ${create_op}"
    exit 1
  fi

  info "Service account создан: ${sa_id}"
  add_out="$(YC_TOKEN="${YC_TOKEN}" yc resource-manager folder add-access-binding "${FOLDER_ID}" --role "${TEST_ROLE}" --service-account-id "${sa_id}" --async)"
  add_op="$(printf '%s\n' "${add_out}" | extract_op_id)"
  if [[ -z "${add_op}" ]]; then
    err "Не удалось получить operation id для add-access-binding"
    exit 1
  fi

  info "Add access binding operation: ${add_op}"
  if ! poll_operation "${add_op}" "${TIMEOUT_SECONDS}" >/dev/null; then
    err "YC IAM add-access-binding завис дольше ${TIMEOUT_SECONDS}s"
    warn "Проверь: yc operation get ${add_op}"
    warn "Возможен внешний сбой IAM backend; cluster apply вероятно зависнет на folder IAM bindings"
    warn "Для cleanup позже: yc resource-manager folder remove-access-binding ${FOLDER_ID} --role ${TEST_ROLE} --service-account-id ${sa_id} --async"
    warn "И затем: yc iam service-account delete ${sa_id} --async"
    exit 2
  fi

  info "Binding выдан, проверяем remove-access-binding"
  remove_out="$(YC_TOKEN="${YC_TOKEN}" yc resource-manager folder remove-access-binding "${FOLDER_ID}" --role "${TEST_ROLE}" --service-account-id "${sa_id}" --async)"
  remove_op="$(printf '%s\n' "${remove_out}" | extract_op_id)"
  if [[ -z "${remove_op}" ]]; then
    err "Не удалось получить operation id для remove-access-binding"
    exit 1
  fi

  if ! poll_operation "${remove_op}" "${TIMEOUT_SECONDS}" >/dev/null; then
    err "YC IAM remove-access-binding завис дольше ${TIMEOUT_SECONDS}s"
    warn "Проверь: yc operation get ${remove_op}"
    warn "Для cleanup позже: yc iam service-account delete ${sa_id} --async"
    exit 2
  fi

  info "Binding снят, удаляем временный service account"
  delete_out="$(YC_TOKEN="${YC_TOKEN}" yc iam service-account delete "${sa_id}" --async)"
  delete_op="$(printf '%s\n' "${delete_out}" | extract_op_id)"
  if [[ -z "${delete_op}" ]]; then
    err "Не удалось получить operation id для delete service account"
    exit 1
  fi

  if ! poll_operation "${delete_op}" "${TIMEOUT_SECONDS}" >/dev/null; then
    err "YC IAM delete service account завис дольше ${TIMEOUT_SECONDS}s"
    warn "Проверь: yc operation get ${delete_op}"
    warn "Временный service account для cleanup: ${sa_id} (${name})"
    exit 2
  fi

  info "YC IAM smoke-check пройден: create/bind/unbind/delete выполняются в разумное время"
}

main "$@"
