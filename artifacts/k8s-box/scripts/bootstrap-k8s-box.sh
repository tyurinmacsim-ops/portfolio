#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GEN_DIR="${REPO_ROOT}/.generated"
ENV_OUT="${GEN_DIR}/bootstrap-context.env"
JSON_OUT="${GEN_DIR}/bootstrap-context.json"

MODE="${1:-context}"
LOAD_DOTENV="${LOAD_DOTENV:-true}"
AUTO_REFRESH_YC_TOKEN="${AUTO_REFRESH_YC_TOKEN:-true}"
SKIP_FOLDER_DESTROY="${SKIP_FOLDER_DESTROY:-true}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<USAGE
Использование:
  ./scripts/bootstrap-k8s-box.sh [context|preflight|preflight-iam|plan|apply|plan-vpn|apply-vpn|destroy-vpn|plan-runner|apply-runner|destroy-runner|plan-cluster|apply-cluster|destroy|destroy-cluster|recreate|recreate-cluster]

Режимы:
  context  Собрать значения из repo/k8s/git и записать .generated/bootstrap-context.{env,json}
  preflight То же, что context, плюс базовые проверки готовности (токены/плейсхолдеры/инструменты)
  preflight-iam То же, что preflight, плюс smoke-check YC IAM операций (service account + folder access binding)
  plan     То же, что context, плюс полный terragrunt plan по стеку (folder..argocd)
  apply    То же, что context, плюс полный terragrunt apply по стеку (folder..argocd, auto-approve)
  plan-vpn  То же, что context, плюс terragrunt plan для VPN VM-стека (folder..vpn-vm)
  apply-vpn То же, что context, плюс terragrunt apply для VPN VM-стека (folder..vpn-vm, auto-approve)
  destroy-vpn Удаление VPN VM-стека terragrunt (только vpn-vm, auto-approve)
  plan-runner  То же, что context, плюс terragrunt plan для runner-стека (folder..infra-runner)
  apply-runner То же, что context, плюс terragrunt apply для runner-стека (folder..infra-runner, auto-approve)
  destroy-runner Удаление runner-стека terragrunt (только infra-runner, auto-approve)
  plan-cluster  То же, что context, плюс terragrunt plan только для кластера (folder..test-cluster-k8s)
  apply-cluster То же, что context, плюс terragrunt apply только для кластера (folder..test-cluster-k8s, auto-approve)
  destroy  Полный terragrunt destroy стека (argocd..vault-infra, folder по SKIP_FOLDER_DESTROY)
  destroy-cluster Terragrunt destroy только кластерного слоя (test-cluster-k8s..vpc, folder по SKIP_FOLDER_DESTROY)
  recreate Полный destroy + apply
  recreate-cluster Destroy + apply только для кластерного слоя
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

ensure_tools() {
  command -v awk >/dev/null 2>&1 || { err "Требуется awk"; exit 1; }
  command -v git >/dev/null 2>&1 || { err "Требуется git"; exit 1; }
}

load_local_env() {
  local env_file="${REPO_ROOT}/.env"
  local preserve_names=()
  local preserve_exports=()
  local name=""
  local value=""

  if [[ "${LOAD_DOTENV}" != "true" ]]; then
    return 0
  fi
  if [[ ! -f "${env_file}" ]]; then
    return 0
  fi

  info "Загружаем локальное окружение из ${env_file}"

  while IFS= read -r name; do
    value="${!name}"
    preserve_names+=("${name}")
    preserve_exports+=("export ${name}=$(printf '%q' "${value}")")
  done < <(compgen -v | grep -E '^(K8S_BOX_|TF_VAR_|YC_TOKEN$|GITLAB_TOKEN$|ARGOCD_ADMIN_PASSWORD$)' || true)

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a

  # Уже экспортированные runtime-значения должны иметь приоритет над .env,
  # чтобы не перетирать явные overrides при запуске из shell или CI.
  if [[ "${#preserve_exports[@]}" -gt 0 ]]; then
    for value in "${preserve_exports[@]}"; do
      eval "${value}"
    done
  fi
}

is_placeholder() {
  local v="$1"
  [[ -z "$v" ]] && return 0
  [[ "$v" == "string" ]] && return 0
  [[ "$v" == *"CHANGE_ME"* ]] && return 0
  [[ "$v" == *"<твой_"* ]] && return 0
  return 1
}

default_storage_class() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 0
  fi

  if ! kubectl config current-context >/dev/null 2>&1; then
    return 0
  fi

  kubectl get storageclass \
    --request-timeout=5s \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"|"}{.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class}{"\n"}{end}' \
    2>/dev/null \
    | awk -F'|' '$2=="true" || $3=="true" {print $1; exit}' || true
}

collect_context() {
  local env_hcl="${REPO_ROOT}/env.hcl"
  local k8s_hcl="${REPO_ROOT}/test-cluster-k8s/terragrunt.hcl"
  local vault_hcl="${REPO_ROOT}/vault-infra/terragrunt.hcl"

  [[ -f "$env_hcl" ]] || { err "Не найден env.hcl"; exit 1; }
  [[ -f "$k8s_hcl" ]] || { err "Не найден test-cluster-k8s/terragrunt.hcl"; exit 1; }

  CLOUD_ID="$(hcl_string "$env_hcl" "cloud_id")"
  YC_ZONE="$(hcl_string "$env_hcl" "yc_zone")"
  NETWORK_NAME="$(hcl_string "$env_hcl" "network_name")"
  FOLDER_NAME="$(hcl_string "$env_hcl" "folder_name")"

  CLUSTER_NAME="${K8S_BOX_CLUSTER_NAME:-$(hcl_string "$k8s_hcl" "name")}"
  CLUSTER_VERSION="${K8S_BOX_CLUSTER_VERSION:-$(hcl_string "$k8s_hcl" "cluster_version")}"
  if [[ -z "${CLUSTER_VERSION}" ]]; then
    CLUSTER_VERSION="$(hcl_string "$k8s_hcl" "master_version")"
  fi

  KMS_KEY_NAME="${K8S_BOX_VAULT_KMS_KEY_NAME:-}"
  VAULT_SA_NAME="${K8S_BOX_VAULT_KMS_SA_NAME:-}"
  if [[ -f "$vault_hcl" ]]; then
    if [[ -z "${KMS_KEY_NAME}" ]]; then
      KMS_KEY_NAME="$(hcl_string "$vault_hcl" "kms_key_name")"
    fi
    if [[ -z "${VAULT_SA_NAME}" ]]; then
      VAULT_SA_NAME="$(hcl_string "$vault_hcl" "vault_kms_sa_name")"
    fi
  fi
  [[ -n "${CLUSTER_NAME}" ]] || CLUSTER_NAME="test-cluster"
  [[ -n "${CLUSTER_VERSION}" ]] || CLUSTER_VERSION="1.33"

  DEFAULT_STORAGE_CLASS="$(default_storage_class)"
  if [[ -z "$DEFAULT_STORAGE_CLASS" ]]; then
    DEFAULT_STORAGE_CLASS="yc-network-hdd"
    info "StorageClass по умолчанию пока не найден; используем fallback=${DEFAULT_STORAGE_CLASS}"
  fi

  GIT_REMOTE_URL="$(git -C "$REPO_ROOT" config --get remote.origin.url || true)"
  GIT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$GIT_BRANCH" && "$GIT_BRANCH" != "HEAD" ]] || GIT_BRANCH="main"

  CLUSTER_SECRET_STORE="vault-${CLUSTER_NAME}"
  ALERTMANAGER_SECRET_PATH="infrastructure/monitoring/${CLUSTER_NAME}/alertmanager"

  export CLOUD_ID YC_ZONE NETWORK_NAME FOLDER_NAME CLUSTER_NAME CLUSTER_VERSION
  export KMS_KEY_NAME VAULT_SA_NAME DEFAULT_STORAGE_CLASS
  export GIT_REMOTE_URL GIT_BRANCH CLUSTER_SECRET_STORE ALERTMANAGER_SECRET_PATH
}

preflight_context() {
  local has_issues=0

  if is_placeholder "${CLOUD_ID}"; then
    warn "cloud_id выглядит как плейсхолдер: '${CLOUD_ID}'"
    has_issues=1
  fi

  if is_placeholder "${FOLDER_NAME}"; then
    warn "folder_name выглядит как плейсхолдер: '${FOLDER_NAME}'"
    has_issues=1
  fi

  if [[ -z "${CLUSTER_NAME}" ]]; then
    warn "cluster_name не найден в test-cluster-k8s/terragrunt.hcl"
    has_issues=1
  fi

  if [[ -z "${GIT_REMOTE_URL}" ]]; then
    warn "git remote.origin.url не найден"
    has_issues=1
  fi

  local current_folder_id=""
  current_folder_id="$(target_folder_id)"
  if [[ -n "${current_folder_id}" ]]; then
    info "Целевой folder для bootstrap: name='${FOLDER_NAME}', id='${current_folder_id}'"
  else
    info "Целевой folder для bootstrap: name='${FOLDER_NAME}' (id пока не найден, будет создан на apply)"
  fi

  if [[ "$has_issues" -eq 0 ]]; then
    info "Проверки preflight-контекста пройдены"
  else
    warn "Preflight: найдены потенциальные проблемы (см. предупреждения выше)"
  fi
}

require_runner_bootstrap_env() {
  local runner_registration_token="${K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN:-}"
  local runner_auth_token="${K8S_BOX_GITLAB_RUNNER_TOKEN:-}"
  local runner_token="${runner_registration_token}"
  local gitlab_url="${K8S_BOX_GITLAB_URL:-}"
  local gitlab_api_url="${K8S_BOX_GITLAB_API_URL:-}"

  # Если registration token не задан или это placeholder,
  # пробуем использовать authentication token (glrt-...).
  if is_placeholder "${runner_token}"; then
    runner_token="${runner_auth_token}"
  fi

  if [[ -z "${gitlab_url}" && -n "${gitlab_api_url}" ]]; then
    gitlab_url="${gitlab_api_url%/}"
    gitlab_url="${gitlab_url%/api/v4}"
    export K8S_BOX_GITLAB_URL="${gitlab_url}"
    info "Используем K8S_BOX_GITLAB_URL, вычисленный из K8S_BOX_GITLAB_API_URL: ${gitlab_url}"
  fi

  if is_placeholder "${runner_token}"; then
    err "Для apply-runner требуется K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN (или K8S_BOX_GITLAB_RUNNER_TOKEN)"
    return 1
  fi
  if is_placeholder "${gitlab_url}" || [[ "${gitlab_url}" == "https://gitlab.example.com" ]]; then
    err "Для apply-runner требуется K8S_BOX_GITLAB_URL (пример: https://gitlab.example.com)"
    return 1
  fi

  export K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN="${runner_token}"
  return 0
}

require_vpn_bootstrap_env() {
  local enable_oslogin="${K8S_BOX_VPN_VM_ENABLE_OSLOGIN:-false}"
  local ssh_mode="${K8S_BOX_VPN_VM_SSH_MODE:-native}"
  local ssh_public_key_path="${K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"
  local ssh_private_key_path="${K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_ed25519}"
  local enable_oslogin_normalized=""
  local ssh_mode_normalized=""

  enable_oslogin_normalized="$(printf '%s' "${enable_oslogin}" | tr '[:upper:]' '[:lower:]')"
  ssh_mode_normalized="$(printf '%s' "${ssh_mode}" | tr '[:upper:]' '[:lower:]')"

  if [[ "${ssh_mode_normalized}" != "native" && "${ssh_mode_normalized}" != "yc" ]]; then
    err "K8S_BOX_VPN_VM_SSH_MODE должен быть native или yc"
    exit 1
  fi

  if [[ "${ssh_mode_normalized}" == "yc" ]]; then
    warn "VPN operational-доступ будет идти через yc compute ssh; убедись, что OS Login profile и SSH key уже настроены в организации"
    return 0
  fi

  if [[ "${enable_oslogin_normalized}" == "true" ]]; then
    warn "VPN VM будет создана с OS Login; для operational-доступа лучше использовать K8S_BOX_VPN_VM_SSH_MODE=yc"
    return 0
  fi

  if [[ ! -f "${ssh_public_key_path}" ]]; then
    err "Для VPN VM с отключенным OS Login нужен SSH public key: ${ssh_public_key_path}"
    exit 1
  fi

  if [[ ! -f "${ssh_private_key_path}" ]]; then
    err "Для локального smoke-check VPN нужен SSH private key: ${ssh_private_key_path}"
    exit 1
  fi
}

write_outputs() {
  mkdir -p "$GEN_DIR"

  cat > "$ENV_OUT" <<ENV
# Сгенерировано scripts/bootstrap-k8s-box.sh
CLOUD_ID="${CLOUD_ID}"
YC_ZONE="${YC_ZONE}"
NETWORK_NAME="${NETWORK_NAME}"
FOLDER_NAME="${FOLDER_NAME}"
CLUSTER_NAME="${CLUSTER_NAME}"
CLUSTER_VERSION="${CLUSTER_VERSION}"
KMS_KEY_NAME="${KMS_KEY_NAME}"
VAULT_SA_NAME="${VAULT_SA_NAME}"
DEFAULT_STORAGE_CLASS="${DEFAULT_STORAGE_CLASS}"
GIT_REMOTE_URL="${GIT_REMOTE_URL}"
GIT_BRANCH="${GIT_BRANCH}"
CLUSTER_SECRET_STORE="${CLUSTER_SECRET_STORE}"
ALERTMANAGER_SECRET_PATH="${ALERTMANAGER_SECRET_PATH}"
ENV

  cat > "$JSON_OUT" <<JSON
{
  "cloud_id": "${CLOUD_ID}",
  "yc_zone": "${YC_ZONE}",
  "network_name": "${NETWORK_NAME}",
  "folder_name": "${FOLDER_NAME}",
  "cluster_name": "${CLUSTER_NAME}",
  "cluster_version": "${CLUSTER_VERSION}",
  "kms_key_name": "${KMS_KEY_NAME}",
  "vault_sa_name": "${VAULT_SA_NAME}",
  "default_storage_class": "${DEFAULT_STORAGE_CLASS}",
  "git_remote_url": "${GIT_REMOTE_URL}",
  "git_branch": "${GIT_BRANCH}",
  "cluster_secret_store": "${CLUSTER_SECRET_STORE}",
  "alertmanager_secret_path": "${ALERTMANAGER_SECRET_PATH}"
}
JSON

  info "Контекст записан: ${ENV_OUT}"
  info "Контекст записан: ${JSON_OUT}"
}

resolve_yc_token() {
  if [[ -z "${TF_VAR_yc_token:-}" && -n "${TF_VAR_YC_TOKEN:-}" ]]; then
    export TF_VAR_yc_token="${TF_VAR_YC_TOKEN}"
  fi
  if [[ -z "${TF_VAR_YC_TOKEN:-}" && -n "${TF_VAR_yc_token:-}" ]]; then
    export TF_VAR_YC_TOKEN="${TF_VAR_yc_token}"
  fi

  if [[ -n "${TF_VAR_yc_token:-}" ]]; then
    info "Используем явно заданный TF_VAR_yc_token из окружения"
    return 0
  fi

  if [[ -n "${YC_TOKEN:-}" ]]; then
    export TF_VAR_YC_TOKEN="${YC_TOKEN}"
    export TF_VAR_yc_token="${YC_TOKEN}"
    info "Используем TF_VAR_yc_token из YC_TOKEN"
    return 0
  fi

  # Если явного токена нет, тогда пытаемся взять свежий токен из текущего yc-профиля.
  if [[ "${AUTO_REFRESH_YC_TOKEN}" == "true" ]] && command -v yc >/dev/null 2>&1; then
    local fresh_token
    fresh_token="$(yc iam create-token 2>/dev/null || true)"
    if [[ -n "${fresh_token}" ]]; then
      export TF_VAR_YC_TOKEN="${fresh_token}"
      export TF_VAR_yc_token="${fresh_token}"
      info "Используем свежий TF_VAR_yc_token из 'yc iam create-token'"
      return 0
    fi
    warn "Не удалось обновить IAM-токен через yc; пробуем существующий TF_VAR_yc_token/YC_TOKEN"
  fi

  if command -v yc >/dev/null 2>&1; then
    local token
    token="$(yc iam create-token 2>/dev/null || true)"
    if [[ -n "${token}" ]]; then
      export TF_VAR_YC_TOKEN="${token}"
      export TF_VAR_yc_token="${token}"
      info "Используем TF_VAR_yc_token из 'yc iam create-token'"
      return 0
    fi
  fi

  err "TF_VAR_YC_TOKEN/TF_VAR_yc_token не задан и не был автоматически определен (YC_TOKEN/yc iam create-token)."
  return 1
}

resolve_gitlab_token() {
  if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    return 0
  fi

  if [[ -n "${GITLAB_ACCESS_TOKEN:-}" ]]; then
    export GITLAB_TOKEN="${GITLAB_ACCESS_TOKEN}"
    info "Используем GITLAB_TOKEN из GITLAB_ACCESS_TOKEN"
    return 0
  fi

  if command -v glab >/dev/null 2>&1; then
    local token
    token="$(glab auth token 2>/dev/null || true)"
    if [[ -n "${token}" ]]; then
      export GITLAB_TOKEN="${token}"
      info "Используем GITLAB_TOKEN из 'glab auth token'"
      return 0
    fi
  fi

  warn "GITLAB_TOKEN не найден. Модуль ArgoCD с gitlab provider может завершиться ошибкой на plan/apply."
  return 0
}

ensure_argocd_repo_auth() {
  if [[ -z "${K8S_BOX_GITLAB_REPO_TOKEN:-}" && -n "${GITLAB_TOKEN:-}" ]]; then
    export K8S_BOX_GITLAB_REPO_TOKEN="${GITLAB_TOKEN}"
  fi

  [[ -n "${K8S_BOX_GITLAB_REPO_TOKEN:-}" ]]
}

run_terragrunt() {
  local cmd="$1"
  local target="${2:-full}"

  command -v terragrunt >/dev/null 2>&1 || { err "Для режима ${cmd} требуется terragrunt"; exit 1; }

  resolve_yc_token || exit 1
  resolve_gitlab_token || true

  export TF_IN_AUTOMATION=1
  export TF_INPUT=0
  export TG_NON_INTERACTIVE=true

  local tg_action
  local tg_auto_arg=""
  case "$cmd" in
    plan)
      tg_action="plan"
      ;;
    apply)
      tg_action="apply"
      tg_auto_arg="-auto-approve"
      ;;
    destroy)
      tg_action="destroy"
      tg_auto_arg="-auto-approve"
      ;;
    *)
      err "Неподдерживаемая terragrunt-команда: ${cmd}"
      exit 1
      ;;
  esac

  local modules=()
  case "${target}" in
    vpn)
      if [[ "${cmd}" == "destroy" ]]; then
        modules=(
          vpn-vm
        )
      else
        modules=(
          folder
          vpc
          vpn-vm
        )
      fi
      ;;
    runner)
      if [[ "${cmd}" == "destroy" ]]; then
        modules=(
          infra-runner
        )
      else
        modules=(
          folder
          vpc
          security-group
          infra-runner
        )
      fi
      ;;
    cluster)
      if [[ "${cmd}" == "destroy" ]]; then
        modules=(
          test-cluster-k8s
          security-group
          vpc
        )
      else
        modules=(
          folder
          vpc
          security-group
          test-cluster-k8s
        )
      fi
      ;;
    full)
      if [[ "${cmd}" == "destroy" ]]; then
        modules=(
          test-cluster-k8s
          security-group
          vpc
          vault-infra
        )
      else
        modules=(
          folder
          vpc
          security-group
          test-cluster-k8s
          vault-infra
        )
      fi
      ;;
    *)
      err "Неподдерживаемая цель bootstrap: ${target}"
      exit 1
      ;;
  esac

  if [[ "${target}" == "full" && "${cmd}" == "destroy" ]]; then
    if cluster_state_exists; then
      if [[ -n "${tg_auto_arg}" ]]; then
        run_argocd_if_ready "${cmd}" "${tg_action}" "${tg_auto_arg}"
      else
        run_argocd_if_ready "${cmd}" "${tg_action}"
      fi
    else
      warn "Пропускаем argocd destroy: не найден cluster state"
    fi
  fi

  local module
  for module in "${modules[@]}"; do
    local module_has_auto_arg="false"
    if [[ -n "${tg_auto_arg}" ]]; then
      module_has_auto_arg="true"
    fi

    if [[ "${module}" == "folder" && ( "${cmd}" == "plan" || "${cmd}" == "apply" ) ]]; then
      remove_stale_folder_state_if_needed
      import_existing_folder_if_needed
    fi

    if [[ "${module}" == "test-cluster-k8s" && ( "${cmd}" == "plan" || "${cmd}" == "apply" ) ]]; then
      configure_existing_cluster_service_accounts_if_needed
    fi

    if [[ "${module}" == "vault-infra" && "${cmd}" == "destroy" ]]; then
      disable_vault_kms_deletion_protection
      info "Запускаем terragrunt ${tg_action} в ${module}"
      if [[ "${module_has_auto_arg}" == "true" ]]; then
        (cd "${REPO_ROOT}/${module}" && terragrunt --non-interactive "${tg_action}" "${tg_auto_arg}" -var=kms_key_deletion_protection=false)
      else
        (cd "${REPO_ROOT}/${module}" && terragrunt --non-interactive "${tg_action}" -var=kms_key_deletion_protection=false)
      fi
      continue
    fi

    info "Запускаем terragrunt ${tg_action} в ${module}"
    if [[ "${module_has_auto_arg}" == "true" ]]; then
      (cd "${REPO_ROOT}/${module}" && terragrunt --non-interactive "${tg_action}" "${tg_auto_arg}")
    else
      (cd "${REPO_ROOT}/${module}" && terragrunt --non-interactive "${tg_action}")
    fi

    if [[ "${module}" == "test-cluster-k8s" && "${cmd}" == "apply" ]]; then
      refresh_kubeconfig_or_fail
    fi
  done

  if [[ "${cmd}" == "destroy" ]]; then
    if [[ "${target}" != "runner" && "${SKIP_FOLDER_DESTROY}" != "true" ]]; then
      info "Запускаем terragrunt destroy в folder"
      if [[ -n "${tg_auto_arg}" ]]; then
        (cd "${REPO_ROOT}/folder" && terragrunt --non-interactive destroy "${tg_auto_arg}")
      else
        (cd "${REPO_ROOT}/folder" && terragrunt --non-interactive destroy)
      fi
    else
      if [[ "${target}" != "runner" ]]; then
        warn "Пропускаем folder destroy (SKIP_FOLDER_DESTROY=true). Установи SKIP_FOLDER_DESTROY=false, чтобы удалить и folder"
      fi
    fi
    return 0
  fi

  if [[ "${target}" == "full" ]]; then
    if [[ -n "${tg_auto_arg}" ]]; then
      run_argocd_if_ready "${cmd}" "${tg_action}" "${tg_auto_arg}"
    else
      run_argocd_if_ready "${cmd}" "${tg_action}"
    fi
  else
    if [[ "${target}" == "cluster" ]]; then
      info "Режим cluster-only: пропускаем модули vault-infra и argocd"
    fi
  fi
}

cluster_id_from_state() {
  local raw
  raw="$(cd "${REPO_ROOT}/test-cluster-k8s" && terragrunt output -raw cluster_id 2>/dev/null || true)"
  raw="$(printf '%s\n' "${raw}" | awk '/^cat[[:alnum:]]+$/ {print; exit}')"
  printf '%s' "${raw}"
}

cluster_state_exists() {
  local cluster_id
  local cluster_name
  cluster_id="$(cluster_id_from_state)"
  cluster_name="$(cluster_name_from_state)"
  [[ -n "${cluster_id}" && -n "${cluster_name}" ]]
}

cluster_name_from_state() {
  local raw
  raw="$(cd "${REPO_ROOT}/test-cluster-k8s" && terragrunt output -raw cluster_name 2>/dev/null || true)"
  raw="$(printf '%s\n' "${raw}" | awk '/^[-_.[:alnum:]]+$/ {print; exit}')"
  printf '%s' "${raw}"
}

cluster_context_name() {
  local cluster_name
  cluster_name="$(cluster_name_from_state)"
  [[ -n "${cluster_name}" ]] || return 1
  printf 'yc-%s' "${cluster_name}"
}

refresh_kubeconfig_or_fail() {
  command -v yc >/dev/null 2>&1 || { err "Для получения kubeconfig для модуля argocd требуется yc"; return 1; }
  local cluster_id
  cluster_id="$(cluster_id_from_state)"
  [[ -n "${cluster_id}" ]] || { err "cluster_id не найден в state test-cluster-k8s"; return 1; }

  info "Обновляем kubeconfig для cluster id=${cluster_id}"
  if yc managed-kubernetes cluster get-credentials --id "${cluster_id}" --external --force >/dev/null 2>&1; then
    return 0
  fi
  if yc k8s cluster get-credentials --id "${cluster_id}" --external --force >/dev/null 2>&1; then
    return 0
  fi

  err "Не удалось обновить kubeconfig для cluster id=${cluster_id}"
  return 1
}

folder_resource_exists_in_state() {
  local folder_resource_addr='yandex_resourcemanager_folder.folders["k8s-box"]'
  (
    cd "${REPO_ROOT}/folder" \
      && terragrunt state list 2>/dev/null \
      | grep -Fxq "${folder_resource_addr}"
  )
}

folder_state_id() {
  local folder_resource_addr='yandex_resourcemanager_folder.folders["k8s-box"]'
  (
    cd "${REPO_ROOT}/folder" \
      && terragrunt state show "${folder_resource_addr}" 2>/dev/null \
      | awk -F' = ' '/^[[:space:]]*id[[:space:]]*=/ {gsub(/"/, "", $2); print $2; exit}'
  )
}

folder_exists_by_id() {
  local folder_id="$1"
  [[ -n "${folder_id}" ]] || return 1
  if ! command -v yc >/dev/null 2>&1; then
    warn "Не найден yc CLI, пропускаем проверку устаревшего folder state по id"
    return 0
  fi
  yc resource-manager folder get --id "${folder_id}" --format json >/dev/null 2>&1
}

existing_folder_id_by_name() {
  local cloud_id="$1"
  local folder_name="$2"
  yc resource-manager folder list \
    --cloud-id "${cloud_id}" \
    --format json \
    --jq ".[] | select(.name==\"${folder_name}\") | select(.status==\"ACTIVE\") | .id" \
    2>/dev/null \
    | head -n1 || true
}

service_account_id_by_name() {
  local folder_id="$1"
  local service_account_name="$2"
  [[ -n "${folder_id}" && -n "${service_account_name}" ]] || return 0
  yc iam service-account list \
    --folder-id "${folder_id}" \
    --format json \
    --jq ".[] | select(.name==\"${service_account_name}\") | .id" \
    2>/dev/null \
    | head -n1 || true
}

first_existing_service_account_id() {
  local folder_id="$1"
  shift
  local service_account_name=""
  local service_account_id=""

  [[ -n "${folder_id}" ]] || return 0

  for service_account_name in "$@"; do
    [[ -n "${service_account_name}" ]] || continue
    service_account_id="$(service_account_id_by_name "${folder_id}" "${service_account_name}")"
    if [[ -n "${service_account_id}" ]]; then
      printf '%s|%s\n' "${service_account_id}" "${service_account_name}"
      return 0
    fi
  done
}

target_folder_id() {
  local state_folder_id=""
  state_folder_id="$(folder_state_id)"
  if [[ -n "${state_folder_id}" ]] && folder_exists_by_id "${state_folder_id}"; then
    printf '%s' "${state_folder_id}"
    return 0
  fi

  existing_folder_id_by_name "${CLOUD_ID:-}" "${FOLDER_NAME:-}"
}

configure_existing_cluster_service_accounts_if_needed() {
  if [[ "${K8S_BOX_USE_EXISTING_SA:-false}" == "true" ]]; then
    if [[ -n "${K8S_BOX_MASTER_SERVICE_ACCOUNT_ID:-}" && -n "${K8S_BOX_NODE_SERVICE_ACCOUNT_ID:-}" ]]; then
      return 0
    fi
  fi

  command -v yc >/dev/null 2>&1 || return 0

  local folder_id
  folder_id="$(target_folder_id)"
  [[ -n "${folder_id}" ]] || return 0

  local master_candidates=(
    "k8s-service-account-${FOLDER_NAME}-${CLUSTER_NAME}"
    "k8s-service-account-${CLUSTER_NAME}"
    "k8s-service-account-k8s-cluster"
  )
  local node_candidates=(
    "k8s-node-account-${FOLDER_NAME}-${CLUSTER_NAME}"
    "k8s-node-account-${CLUSTER_NAME}"
    "k8s-node-account-k8s-cluster"
  )
  local master_id=""
  local node_id=""
  local master_name=""
  local node_name=""
  local master_match=""
  local node_match=""

  master_match="$(first_existing_service_account_id "${folder_id}" "${master_candidates[@]}")"
  node_match="$(first_existing_service_account_id "${folder_id}" "${node_candidates[@]}")"

  if [[ -n "${master_match}" ]]; then
    master_id="${master_match%%|*}"
    master_name="${master_match#*|}"
  fi

  if [[ -n "${node_match}" ]]; then
    node_id="${node_match%%|*}"
    node_name="${node_match#*|}"
  fi

  if [[ -n "${master_id}" && -n "${node_id}" ]]; then
    export K8S_BOX_USE_EXISTING_SA="true"
    export K8S_BOX_MASTER_SERVICE_ACCOUNT_ID="${master_id}"
    export K8S_BOX_NODE_SERVICE_ACCOUNT_ID="${node_id}"
    info "Найдены существующие service account для cluster '${CLUSTER_NAME}' в folder ${folder_id}; используем reuse existing SA"
    info "master='${master_name}' node='${node_name}'"
    return 0
  fi

  if [[ -n "${master_id}" || -n "${node_id}" ]]; then
    warn "В folder ${folder_id} найден только один из ожидаемых cluster service account для '${CLUSTER_NAME}'"
    warn "master=${master_id:-missing} node=${node_id:-missing}"
    warn "Если это остатки старого окружения, либо дочисти их, либо явно задай K8S_BOX_USE_EXISTING_SA=true и оба *_SERVICE_ACCOUNT_ID"
  fi
}

remove_stale_folder_state_if_needed() {
  local folder_resource_addr='yandex_resourcemanager_folder.folders["k8s-box"]'

  if ! folder_resource_exists_in_state; then
    return 0
  fi

  local state_folder_id
  state_folder_id="$(folder_state_id)"
  if [[ -z "${state_folder_id}" ]]; then
    return 0
  fi

  if folder_exists_by_id "${state_folder_id}"; then
    return 0
  fi

  warn "Folder id '${state_folder_id}' не найден в облаке, удаляем устаревшую запись из terraform state"
  (
    cd "${REPO_ROOT}/folder" \
      && terragrunt --non-interactive state rm "${folder_resource_addr}"
  )
}

import_existing_folder_if_needed() {
  local cloud_id="${CLOUD_ID:-}"
  local folder_name="${FOLDER_NAME:-}"
  local folder_resource_addr='yandex_resourcemanager_folder.folders["k8s-box"]'

  if [[ -z "${cloud_id}" || -z "${folder_name}" ]]; then
    return 0
  fi

  if folder_resource_exists_in_state; then
    return 0
  fi

  local existing_folder_id
  existing_folder_id="$(existing_folder_id_by_name "${cloud_id}" "${folder_name}")"
  if [[ -z "${existing_folder_id}" ]]; then
    return 0
  fi

  info "Folder '${folder_name}' уже существует в cloud '${cloud_id}', импортируем в state"
  (
    cd "${REPO_ROOT}/folder" \
      && terragrunt --non-interactive import "${folder_resource_addr}" "${existing_folder_id}"
  )
}

disable_vault_kms_deletion_protection() {
  if [[ ! -d "${REPO_ROOT}/vault-infra" ]]; then
    return 0
  fi

  info "Отключаем KMS deletion protection в vault-infra перед destroy"
  (
    cd "${REPO_ROOT}/vault-infra" \
      && terragrunt --non-interactive apply -auto-approve -var='kms_key_deletion_protection=false'
  )
}

has_cluster_context() {
  local context_name="$1"
  command -v kubectl >/dev/null 2>&1 || return 1
  kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "${context_name}"
}

run_argocd_if_ready() {
  local cmd="$1"
  local tg_action="$2"
  shift 2
  local tg_extra_args=("$@")

  if [[ ! -d "${REPO_ROOT}/argocd" ]]; then
    warn "Не найдена директория модуля argocd, пропускаем"
    return 0
  fi

  local context_name
  if ! context_name="$(cluster_context_name)"; then
    if [[ "${cmd}" == "plan" || "${cmd}" == "destroy" ]]; then
      warn "Пропускаем argocd ${cmd}: cluster state пока не найден"
      return 0
    fi
    err "cluster_name не найден в state test-cluster-k8s; невозможно запустить argocd"
    exit 1
  fi

  if ! has_cluster_context "${context_name}"; then
    if [[ "${cmd}" == "plan" ]]; then
      warn "Kube context ${context_name} не найден, пробуем обновить kubeconfig"
      if ! refresh_kubeconfig_or_fail; then
        warn "Пропускаем argocd plan: отсутствует kube context"
        return 0
      fi
    elif [[ "${cmd}" == "destroy" ]]; then
      warn "Kube context ${context_name} не найден, пробуем обновить kubeconfig"
      if ! refresh_kubeconfig_or_fail; then
        warn "Пропускаем argocd destroy: отсутствует kube context"
        return 0
      fi
    else
      refresh_kubeconfig_or_fail || { err "Не удалось обновить kubeconfig перед argocd ${cmd}"; exit 1; }
    fi
  fi

  if ! has_cluster_context "${context_name}"; then
    if [[ "${cmd}" == "plan" || "${cmd}" == "destroy" ]]; then
      warn "Пропускаем argocd ${cmd}: kube context ${context_name} все еще отсутствует"
      return 0
    fi
    err "Отсутствует kube context ${context_name}; невозможно выполнить argocd ${cmd}"
    exit 1
  fi

  if ! ensure_argocd_repo_auth; then
    if [[ "${cmd}" == "plan" || "${cmd}" == "destroy" ]]; then
      warn "Пропускаем argocd ${cmd}: не задан K8S_BOX_GITLAB_REPO_TOKEN (или GITLAB_TOKEN)"
      return 0
    fi
    err "Для argocd ${cmd} требуется K8S_BOX_GITLAB_REPO_TOKEN (или GITLAB_TOKEN)"
    exit 1
  fi

  info "Запускаем terragrunt ${tg_action} в argocd"
  (cd "${REPO_ROOT}/argocd" && terragrunt --non-interactive "${tg_action}" "${tg_extra_args[@]}")
}

main() {
  load_local_env
  ensure_tools

  case "$MODE" in
    context)
      collect_context
      write_outputs
      ;;
    preflight)
      collect_context
      write_outputs
      preflight_context
      resolve_yc_token || true
      resolve_gitlab_token || true
      ;;
    preflight-iam)
      collect_context
      write_outputs
      preflight_context
      resolve_yc_token || true
      resolve_gitlab_token || true
      "${SCRIPT_DIR}/yc-iam-smoke-check.sh"
      ;;
    plan)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt plan full
      ;;
    plan-vpn)
      collect_context
      write_outputs
      preflight_context
      require_vpn_bootstrap_env
      run_terragrunt plan vpn
      ;;
    apply-vpn)
      collect_context
      write_outputs
      preflight_context
      require_vpn_bootstrap_env
      run_terragrunt apply vpn
      ;;
    destroy-vpn)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt destroy vpn
      ;;
    plan-runner)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt plan runner
      ;;
    apply)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt apply full
      ;;
    apply-runner)
      collect_context
      write_outputs
      preflight_context
      require_runner_bootstrap_env
      run_terragrunt apply runner
      ;;
    destroy-runner)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt destroy runner
      ;;
    destroy)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt destroy full
      ;;
    plan-cluster)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt plan cluster
      ;;
    apply-cluster)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt apply cluster
      ;;
    destroy-cluster)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt destroy cluster
      ;;
    recreate)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt destroy full
      run_terragrunt apply full
      ;;
    recreate-cluster)
      collect_context
      write_outputs
      preflight_context
      run_terragrunt destroy cluster
      run_terragrunt apply cluster
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main
