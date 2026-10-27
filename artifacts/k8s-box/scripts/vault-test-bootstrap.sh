#!/usr/bin/env bash
set -euo pipefail

VAULT_NS="${VAULT_NS:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_INIT_FILE="${VAULT_INIT_FILE:-${HOME}/.k8s-box/vault/test-init.json}"
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-180}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_tools() {
  command -v kubectl >/dev/null 2>&1 || fail "Не найден kubectl"
  command -v jq >/dev/null 2>&1 || fail "Не найден jq"

  local kube_context
  kube_context="$(kubectl config current-context 2>/dev/null || true)"
  [[ -n "${kube_context}" ]] || fail "Не настроен kubectl context"
}

wait_for_vault_pod() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SEC))
  while (( SECONDS < deadline )); do
    if kubectl -n "${VAULT_NS}" get pod "${VAULT_POD}" >/dev/null 2>&1; then
      local phase
      phase="$(kubectl -n "${VAULT_NS}" get pod "${VAULT_POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [[ "${phase}" == "Running" ]]; then
        return 0
      fi
    fi
    sleep 2
  done
  return 1
}

vault_status_json() {
  local out rc
  set +e
  out="$(kubectl -n "${VAULT_NS}" exec "${VAULT_POD}" -- vault status -format=json 2>/dev/null)"
  rc=$?
  set -e
  if [[ ${rc} -ne 0 && ${rc} -ne 2 ]]; then
    return ${rc}
  fi
  printf '%s' "${out}"
}

initialize_if_needed() {
  local status_json initialized
  status_json="$(vault_status_json)"
  initialized="$(printf '%s' "${status_json}" | jq -r '.initialized')"

  if [[ "${initialized}" == "true" ]]; then
    return 0
  fi

  info "Vault не инициализирован, запускаем vault operator init"
  mkdir -p "$(dirname "${VAULT_INIT_FILE}")"

  if [[ -f "${VAULT_INIT_FILE}" ]]; then
    local backup="${VAULT_INIT_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    warn "Найден существующий init-файл, переносим в ${backup}"
    mv "${VAULT_INIT_FILE}" "${backup}"
  fi

  local tmp_file
  tmp_file="${VAULT_INIT_FILE}.tmp"
  kubectl -n "${VAULT_NS}" exec "${VAULT_POD}" -- vault operator init -format=json > "${tmp_file}"
  chmod 600 "${tmp_file}"
  mv "${tmp_file}" "${VAULT_INIT_FILE}"
  info "Данные инициализации сохранены в ${VAULT_INIT_FILE}"
}

unseal_if_needed() {
  local status_json initialized sealed
  status_json="$(vault_status_json)"
  initialized="$(printf '%s' "${status_json}" | jq -r '.initialized')"
  sealed="$(printf '%s' "${status_json}" | jq -r '.sealed')"

  if [[ "${initialized}" != "true" ]]; then
    fail "Vault не инициализирован после попытки init"
  fi

  if [[ "${sealed}" == "false" ]]; then
    info "Vault уже распечатан (unsealed)"
    return 0
  fi

  [[ -f "${VAULT_INIT_FILE}" ]] || fail "Vault запечатан, но отсутствует init-файл: ${VAULT_INIT_FILE}"

  local threshold idx
  threshold="$(jq -r '.unseal_threshold // 3' "${VAULT_INIT_FILE}")"
  [[ "${threshold}" =~ ^[0-9]+$ ]] || threshold=3

  info "Vault запечатан, применяем до ${threshold} unseal-ключей"
  for (( idx=0; idx<threshold; idx++ )); do
    local key
    key="$(jq -r ".unseal_keys_b64[${idx}] // empty" "${VAULT_INIT_FILE}")"
    [[ -n "${key}" ]] || fail "Unseal-ключ #${idx} отсутствует в ${VAULT_INIT_FILE}"
    kubectl -n "${VAULT_NS}" exec "${VAULT_POD}" -- vault operator unseal "${key}" >/dev/null

    status_json="$(vault_status_json)"
    sealed="$(printf '%s' "${status_json}" | jq -r '.sealed')"
    if [[ "${sealed}" == "false" ]]; then
      info "Vault успешно распечатан"
      return 0
    fi
  done

  fail "Vault все еще запечатан после применения доступных ключей"
}

print_summary() {
  local status_json
  status_json="$(vault_status_json)"
  printf '%s' "${status_json}" \
    | jq -r '"Initialized=\(.initialized) Sealed=\(.sealed) HAEnabled=\(.ha_enabled) Version=\(.version)"'
}

main() {
  require_tools
  wait_for_vault_pod || fail "Vault pod ${VAULT_NS}/${VAULT_POD} не перешел в Running за ${WAIT_TIMEOUT_SEC} сек"
  initialize_if_needed
  unseal_if_needed
  print_summary
}

main "$@"
