#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${SCRIPT_DIR}/../../infrastructure}"

errors=0
warnings=0

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; errors=$((errors + 1)); }

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

read_block_value() {
  local file="$1"
  local block="$2"
  local key="$3"
  [[ -f "${file}" ]] || return 1
  awk -v block="${block}" -v key="${key}" '
    $0 ~ "^" block ":[[:space:]]*$" { in_block=1; next }
    in_block && /^[^[:space:]]/ { in_block=0 }
    in_block {
      line=$0
      gsub(/^[[:space:]]+/, "", line)
      split(line, parts, /:[[:space:]]*/)
      if (parts[1] == key) {
        value=line
        sub("^[^:]+:[[:space:]]*", "", value)
        sub("[[:space:]]+#.*$", "", value)
        print value
        exit
      }
    }
  ' "${file}"
}

has_pattern() {
  local path="$1"
  local pattern="$2"
  rg -n "${pattern}" "${path}" >/dev/null 2>&1
}

check_file_exists() {
  local file="$1"
  [[ -f "${file}" ]] || fail "Отсутствует файл: ${file}"
}

main() {
  local vault_values="${INFRA_REPO_DIR}/vault/values.yaml"
  local vault_base_values="${INFRA_REPO_DIR}/vault/manifests/values-ha-raft.yaml"
  local vault_backup="${INFRA_REPO_DIR}/vault/manifests/backup/backup-cronjob.yaml"
  local obs_values="${INFRA_REPO_DIR}/observability/values.yaml"
  local obs_vm_values="${INFRA_REPO_DIR}/observability/manifests/victoria/victoria-metrics-k8s-stack.values.yaml"
  local obs_prom_values="${INFRA_REPO_DIR}/observability/manifests/prometheus/kube-prometheus-stack.values.yaml"
  local obs_loki_values="${INFRA_REPO_DIR}/observability/manifests/loki/loki.values.yaml"
  local obs_external_secret="${INFRA_REPO_DIR}/observability/manifests/external-secrets/monitoring-alertmanager-telegram-bot.yaml"
  local obs_vso_secret="${INFRA_REPO_DIR}/observability/manifests/vso/monitoring-alertmanager-telegram-bot.yaml"

  check_file_exists "${vault_values}"
  check_file_exists "${vault_base_values}"
  check_file_exists "${vault_backup}"
  check_file_exists "${obs_values}"
  check_file_exists "${obs_loki_values}"
  check_file_exists "${obs_external_secret}"
  check_file_exists "${obs_vso_secret}"

  local vault_profile obs_profile
  local obs_stack
  local backup_enabled backup_enabled_in_test
  local telegram_enabled secret_provider secret_sync_in_test
  vault_profile="$(read_value "${vault_values}" "profile" || true)"
  obs_profile="$(read_value "${obs_values}" "profile" || true)"
  obs_stack="$(read_value "${obs_values}" "observabilityStack" || true)"
  [[ -n "${obs_stack}" ]] || obs_stack="vm-loki-grafana"
  backup_enabled="$(read_value "${vault_values}" "enableBackupManifests" || echo "false")"
  backup_enabled_in_test="$(read_value "${vault_values}" "enableBackupManifestsInTest" || echo "false")"
  telegram_enabled="$(read_block_value "${obs_values}" "alertmanagerTelegram" "enabled" || echo "true")"
  secret_provider="$(read_block_value "${obs_values}" "alertmanagerTelegram" "secretProvider" || echo "vso")"
  secret_sync_in_test="$(read_block_value "${obs_values}" "alertmanagerTelegram" "enableSecretSyncInTest" || echo "false")"

  if [[ "${obs_stack}" != "vm-loki-grafana" && "${obs_stack}" != "prom-loki-grafana" ]]; then
    fail "Неподдерживаемый observabilityStack=${obs_stack} (допустимо: vm-loki-grafana, prom-loki-grafana)"
  fi
  case "${secret_provider}" in
    vso|external-secrets|manual) ;;
    *) fail "Неподдерживаемый alertmanagerTelegram.secretProvider=${secret_provider} (допустимо: vso, external-secrets, manual)" ;;
  esac

  info "Обнаружены профили: vault=${vault_profile:-unknown}, observability=${obs_profile:-unknown}, stack=${obs_stack}, secretProvider=${secret_provider}"

  if [[ "${obs_stack}" == "vm-loki-grafana" ]]; then
    check_file_exists "${obs_vm_values}"
  else
    check_file_exists "${obs_prom_values}"
  fi

  if [[ "${vault_profile}" == "test" && "${backup_enabled_in_test}" != "false" ]]; then
    warn "Для Vault test-профиля enableBackupManifestsInTest=${backup_enabled_in_test}. Рекомендуется false."
  fi

  if [[ "${obs_profile}" == "test" && "${secret_sync_in_test}" != "false" ]]; then
    warn "Для Observability test-профиля alertmanagerTelegram.enableSecretSyncInTest=${secret_sync_in_test}. Рекомендуется false."
  fi

  if [[ "${vault_profile}" == "prod" ]]; then
    has_pattern "${vault_base_values}" "<CHANGE_ME_KMS_KEY_ID>" && fail "Vault prod still has <CHANGE_ME_KMS_KEY_ID>"
    has_pattern "${vault_base_values}" "vault.example.internal" && warn "Vault ingress host все еще содержит значение-пример по умолчанию"

    if [[ "${backup_enabled}" == "true" ]]; then
      has_pattern "${vault_backup}" "<CHANGE_ME_BACKUP_BUCKET>" && fail "Плейсхолдер Vault backup bucket не заменен"
    fi
  fi

  if [[ "${obs_profile}" == "prod" ]]; then
    if [[ "${obs_stack}" == "vm-loki-grafana" ]]; then
      has_pattern "${obs_vm_values}" "CHANGE_ME_STORAGE_CLASS" && fail "Observability prod (VM stack): не заменен CHANGE_ME_STORAGE_CLASS"
      has_pattern "${obs_vm_values}" "CHANGE_ME_CLUSTER_NAME" && fail "Observability prod (VM stack): не заменен CHANGE_ME_CLUSTER_NAME"
      has_pattern "${obs_vm_values}" "CHANGE_ME_GRAFANA_ADMIN_PASSWORD" && fail "Observability prod (VM stack): не заменен CHANGE_ME_GRAFANA_ADMIN_PASSWORD"
    else
      has_pattern "${obs_prom_values}" "CHANGE_ME_STORAGE_CLASS" && fail "Observability prod (Prom stack): не заменен CHANGE_ME_STORAGE_CLASS"
      has_pattern "${obs_prom_values}" "CHANGE_ME_CLUSTER_NAME" && fail "Observability prod (Prom stack): не заменен CHANGE_ME_CLUSTER_NAME"
      has_pattern "${obs_prom_values}" "CHANGE_ME_GRAFANA_ADMIN_PASSWORD" && fail "Observability prod (Prom stack): не заменен CHANGE_ME_GRAFANA_ADMIN_PASSWORD"
      has_pattern "${obs_prom_values}" "CHANGE_ME_TELEGRAM_WARNING_CHAT_ID" && fail "Observability prod (Prom stack): не заменен CHANGE_ME_TELEGRAM_WARNING_CHAT_ID"
      has_pattern "${obs_prom_values}" "CHANGE_ME_TELEGRAM_CRITICAL_CHAT_ID" && fail "Observability prod (Prom stack): не заменен CHANGE_ME_TELEGRAM_CRITICAL_CHAT_ID"
    fi
    has_pattern "${obs_loki_values}" "CHANGE_ME_STORAGE_CLASS" && fail "Loki prod: не заменен CHANGE_ME_STORAGE_CLASS"

    if [[ "${telegram_enabled}" == "true" && "${secret_provider}" == "external-secrets" ]]; then
      has_pattern "${obs_external_secret}" "change-me-cluster-secret-store" && fail "Плейсхолдер ExternalSecret store не заменен"
      has_pattern "${obs_external_secret}" "change-me-alertmanager-secret-path" && fail "Плейсхолдер ExternalSecret path не заменен"
    fi
    if [[ "${telegram_enabled}" == "true" && "${secret_provider}" == "vso" ]]; then
      has_pattern "${obs_vso_secret}" "change-me-monitoring-role" && fail "Плейсхолдер VaultAuth role не заменен"
      has_pattern "${obs_vso_secret}" "change-me-kv-mount" && fail "Плейсхолдер Vault KV mount не заменен"
      has_pattern "${obs_vso_secret}" "change-me-alertmanager-secret-path" && fail "Плейсхолдер Vault secret path не заменен"
    fi
    if [[ "${telegram_enabled}" == "true" && "${secret_provider}" == "manual" ]]; then
      warn "Для prod выбран manual secretProvider: секрет alertmanager-telegram-bot нужно создать вручную до sync."
    fi
  fi

  if (( errors > 0 )); then
    printf '\n[RESULT] FAILED: %d error(s), %d warning(s)\n' "${errors}" "${warnings}" >&2
    exit 1
  fi

  printf '\n[RESULT] OK: %d warning(s)\n' "${warnings}"
}

main "$@"
