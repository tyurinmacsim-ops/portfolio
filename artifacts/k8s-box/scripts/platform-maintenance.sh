#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-600}"
AUTO_BOOTSTRAP_VAULT_TEST="${AUTO_BOOTSTRAP_VAULT_TEST:-true}"
ALLOW_VAULT_OUTOFSYNC_IN_TEST="${ALLOW_VAULT_OUTOFSYNC_IN_TEST:-true}"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${ROOT_DIR}/../infrastructure}"
RUN_SMOKE_CHECK_AFTER_UPGRADE="${RUN_SMOKE_CHECK_AFTER_UPGRADE:-true}"
LOAD_DOTENV="${LOAD_DOTENV:-true}"
AUTO_REFRESH_YC_TOKEN="${AUTO_REFRESH_YC_TOKEN:-true}"
AUTO_FETCH_KUBECONFIG="${AUTO_FETCH_KUBECONFIG:-true}"

PARENT_APPS=(
  infrastructure-vault
  infrastructure-observability
)

CHILD_APPS=()

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Отсутствует обязательная команда: $1"
}

load_local_env() {
  local env_file="${ROOT_DIR}/.env"
  local pre_tf_var_yc_token_upper="${TF_VAR_YC_TOKEN:-}"
  local pre_tf_var_yc_token="${TF_VAR_yc_token:-}"
  local pre_yc_token="${YC_TOKEN:-}"
  local pre_gitlab_token="${GITLAB_TOKEN:-}"

  if [[ "${LOAD_DOTENV}" != "true" ]]; then
    return 0
  fi
  if [[ ! -f "${env_file}" ]]; then
    return 0
  fi

  info "Загружаем локальное окружение из ${env_file}"
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a

  # Значения, уже экспортированные в runtime, имеют приоритет над .env,
  # чтобы не перетирать актуальные учетные данные устаревшими.
  if [[ -n "${pre_tf_var_yc_token_upper}" ]]; then
    export TF_VAR_YC_TOKEN="${pre_tf_var_yc_token_upper}"
  fi
  if [[ -n "${pre_tf_var_yc_token}" ]]; then
    export TF_VAR_yc_token="${pre_tf_var_yc_token}"
  fi
  if [[ -n "${pre_yc_token}" ]]; then
    export YC_TOKEN="${pre_yc_token}"
  fi
  if [[ -n "${pre_gitlab_token}" ]]; then
    export GITLAB_TOKEN="${pre_gitlab_token}"
  fi
}

ensure_yc_token() {
  if [[ -z "${TF_VAR_yc_token:-}" && -n "${TF_VAR_YC_TOKEN:-}" ]]; then
    export TF_VAR_yc_token="${TF_VAR_YC_TOKEN}"
  fi
  if [[ -z "${TF_VAR_YC_TOKEN:-}" && -n "${TF_VAR_yc_token:-}" ]]; then
    export TF_VAR_YC_TOKEN="${TF_VAR_yc_token}"
  fi

  if [[ "${AUTO_REFRESH_YC_TOKEN}" == "true" ]] && command -v yc >/dev/null 2>&1; then
    local fresh_token
    fresh_token="$(yc iam create-token 2>/dev/null || true)"
    if [[ -n "${fresh_token}" ]]; then
      export TF_VAR_YC_TOKEN="${fresh_token}"
      export TF_VAR_yc_token="${fresh_token}"
      info "Используем свежий TF_VAR_yc_token из yc iam create-token"
      return 0
    fi
    warn "Не удалось обновить IAM-токен через yc; пробуем существующий TF_VAR_yc_token/YC_TOKEN"
  fi

  if [[ -n "${TF_VAR_yc_token:-}" ]]; then
    info "Используем TF_VAR_yc_token из окружения"
    return 0
  fi

  if [[ -n "${YC_TOKEN:-}" ]]; then
    export TF_VAR_YC_TOKEN="${YC_TOKEN}"
    export TF_VAR_yc_token="${YC_TOKEN}"
    info "Используем TF_VAR_yc_token из YC_TOKEN"
    return 0
  fi

  require_cmd yc
  local token
  token="$(yc iam create-token 2>/dev/null || true)"
  [[ -n "${token}" ]] || fail "TF_VAR_YC_TOKEN/TF_VAR_yc_token не задан, и yc iam create-token завершился ошибкой"
  export TF_VAR_YC_TOKEN="${token}"
  export TF_VAR_yc_token="${token}"
  info "Используем TF_VAR_yc_token из yc iam create-token"
}

ensure_argocd_repo_auth() {
  if [[ -z "${K8S_BOX_GITLAB_REPO_TOKEN:-}" && -n "${GITLAB_TOKEN:-}" ]]; then
    export K8S_BOX_GITLAB_REPO_TOKEN="${GITLAB_TOKEN}"
  fi

  [[ -n "${K8S_BOX_GITLAB_REPO_USER:-}" ]] || fail "Для модуля argocd требуется K8S_BOX_GITLAB_REPO_USER"
  [[ -n "${K8S_BOX_GITLAB_REPO_TOKEN:-}" ]] || fail "Для модуля argocd требуется K8S_BOX_GITLAB_REPO_TOKEN (или GITLAB_TOKEN)"
}

read_profile() {
  local values_file="$1"
  [[ -f "${values_file}" ]] || return 1
  grep -E '^[[:space:]]*profile:' "${values_file}" \
    | head -n1 \
    | awk -F ':' '{print $2}' \
    | cut -d '#' -f1 \
    | xargs
}

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

detect_observability_stack() {
  local obs_values="${INFRA_REPO_DIR}/observability/values.yaml"
  local stack
  stack="$(read_value "${obs_values}" "observabilityStack" || true)"
  [[ -n "${stack}" ]] || stack="vm-loki-grafana"
  printf '%s' "${stack}"
}

build_child_apps() {
  local stack="$1"

  # Используем объединенный список возможных дочерних Application.
  # Отсутствующие app безопасно пропускаются, зато скрипт не расходится
  # с текущей моделью VSO/ExternalSecrets/manual в infrastructure.
  CHILD_APPS=(
    vault
    monitoring-loki
    monitoring-vault-secrets-operator
    monitoring-external-secrets-operator
    monitoring-alertmanager-vault-secrets
    monitoring-alertmanager-external-secrets
  )
  case "${stack}" in
    vm-loki-grafana) CHILD_APPS+=(monitoring-victoria-metrics-stack) ;;
    prom-loki-grafana) CHILD_APPS+=(monitoring-kube-prometheus-stack) ;;
    *)
      warn "Неподдерживаемый observabilityStack=${stack}; используем fallback на приложения vm-loki-grafana"
      CHILD_APPS+=(monitoring-victoria-metrics-stack)
      ;;
  esac
}

ensure_kube_tools() {
  require_cmd kubectl
  require_cmd jq
}

cluster_id_from_state() {
  local raw
  raw="$(cd "${ROOT_DIR}/test-cluster-k8s" && terragrunt output -raw cluster_id 2>/dev/null || true)"
  raw="$(printf '%s\n' "${raw}" | awk '/^cat[[:alnum:]]+$/ {print; exit}')"
  printf '%s' "${raw}"
}

cluster_name_from_state() {
  local raw
  raw="$(cd "${ROOT_DIR}/test-cluster-k8s" && terragrunt output -raw cluster_name 2>/dev/null || true)"
  raw="$(printf '%s\n' "${raw}" | awk '/^[-_.[:alnum:]]+$/ {print; exit}')"
  printf '%s' "${raw}"
}

cluster_state_exists() {
  local cluster_id
  cluster_id="$(cluster_id_from_state)"
  [[ -n "${cluster_id}" ]]
}

refresh_kubeconfig() {
  require_cmd yc

  local cluster_id
  cluster_id="$(cluster_id_from_state)"
  [[ -n "${cluster_id}" ]] || fail "Отсутствует cluster state; нельзя обновить kubeconfig"

  info "Обновляем kubeconfig для cluster id=${cluster_id}"
  if yc managed-kubernetes cluster get-credentials --id "${cluster_id}" --external --force >/dev/null 2>&1; then
    return 0
  fi
  if yc k8s cluster get-credentials --id "${cluster_id}" --external --force >/dev/null 2>&1; then
    return 0
  fi

  fail "Не удалось получить kubeconfig для cluster id=${cluster_id}"
}

ensure_cluster_context() {
  require_cmd kubectl

  local cluster_name context_name cluster_id
  cluster_name="$(cluster_name_from_state)"
  [[ -n "${cluster_name}" ]] || fail "В terragrunt state отсутствует cluster_name"
  context_name="yc-${cluster_name}"

  if kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "${context_name}"; then
    return 0
  fi

  if [[ "${AUTO_FETCH_KUBECONFIG}" != "true" ]]; then
    cluster_id="$(cluster_id_from_state)"
    fail "Отсутствует kube context ${context_name}. Выполни: yc managed-kubernetes cluster get-credentials --id ${cluster_id:-<cluster_id>} --external --force (или задай AUTO_FETCH_KUBECONFIG=true)"
  fi

  warn "Kube context ${context_name} не найден, обновляем kubeconfig"
  refresh_kubeconfig

  kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "${context_name}" \
    || fail "Kube context ${context_name} все еще отсутствует после обновления"
}

run_terragrunt() {
  local module="$1"
  local action="$2"
  shift 2 || true

  require_cmd terragrunt
  ensure_yc_token

  export TF_IN_AUTOMATION=1
  export TF_INPUT=0
  export TG_NON_INTERACTIVE=true

  local module_dir="${ROOT_DIR}/${module}"
  [[ -d "${module_dir}" ]] || fail "Не найдена директория terragrunt-модуля: ${module_dir}"

  info "terragrunt ${action} in ${module_dir}"
  (cd "${module_dir}" && terragrunt --non-interactive "${action}" "$@")
}

stack_commands_moved_to_bootstrap() {
  local cmd="$1"
  local bootstrap_cmd=""
  case "${cmd}" in
    plan-all) bootstrap_cmd="plan" ;;
    apply-all) bootstrap_cmd="apply" ;;
    destroy-all) bootstrap_cmd="destroy" ;;
    recreate-all) bootstrap_cmd="recreate" ;;
    *) bootstrap_cmd="<mode>" ;;
  esac
  fail "Command '${cmd}' moved to bootstrap-k8s-box.sh. Use: ./scripts/bootstrap-k8s-box.sh ${bootstrap_cmd}"
}

trigger_app_sync() {
  local app="$1"
  kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1 || return 0
  kubectl -n "${ARGOCD_NS}" annotate application "${app}" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  kubectl -n "${ARGOCD_NS}" patch application "${app}" --type merge \
    -p '{"operation":{"sync":{"prune":true,"syncOptions":["CreateNamespace=true"]}}}' >/dev/null
}

wait_app_ready() {
  local app="$1"
  local deadline=$((SECONDS + WAIT_TIMEOUT_SEC))
  local vault_profile=""
  vault_profile="$(read_profile "${INFRA_REPO_DIR}/vault/values.yaml" || true)"

  while (( SECONDS < deadline )); do
    if ! kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1; then
      sleep 3
      continue
    fi

    local sync_status health_status
    sync_status="$(kubectl -n "${ARGOCD_NS}" get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health_status="$(kubectl -n "${ARGOCD_NS}" get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    if [[ "${sync_status}" == "Synced" && "${health_status}" == "Healthy" ]]; then
      return 0
    fi
    if [[ "${app}" == "vault" && "${vault_profile}" == "test" && "${ALLOW_VAULT_OUTOFSYNC_IN_TEST}" == "true" ]]; then
      if [[ "${sync_status}" == "OutOfSync" && "${health_status}" == "Healthy" ]]; then
        warn "App vault is OutOfSync but Healthy (allowed in test mode)"
        return 0
      fi
    fi
    sleep 5
  done

  return 1
}

sync_gitops_apps() {
  ensure_kube_tools
  build_child_apps "$(detect_observability_stack)"

  info "Triggering sync for parent applications"
  local app
  for app in "${PARENT_APPS[@]}"; do
    trigger_app_sync "${app}"
  done

  info "Ждем, пока родительские приложения перейдут в Synced/Healthy"
  for app in "${PARENT_APPS[@]}"; do
    if ! wait_app_ready "${app}"; then
      fail "Приложение не стало готовым вовремя: ${app}"
    fi
  done

  info "Запускаем sync дочерних приложений (если они есть)"
  for app in "${CHILD_APPS[@]}"; do
    trigger_app_sync "${app}"
  done

  info "Ждем, пока дочерние приложения перейдут в Synced/Healthy"
  for app in "${CHILD_APPS[@]}"; do
    if ! kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1; then
      continue
    fi
    if ! wait_app_ready "${app}"; then
      fail "Приложение не стало готовым вовремя: ${app}"
    fi
  done
}

run_vault_observability_upgrade_flow() {
  ensure_kube_tools
  "${SCRIPT_DIR}/preflight-vault-observability.sh"
  sync_gitops_apps
  if [[ "${AUTO_BOOTSTRAP_VAULT_TEST}" == "true" ]]; then
    "${SCRIPT_DIR}/vault-test-bootstrap.sh"
  fi
  "${SCRIPT_DIR}/healthcheck-vault-observability.sh"
  if [[ "${RUN_SMOKE_CHECK_AFTER_UPGRADE}" == "true" ]]; then
    "${SCRIPT_DIR}/service-smoke-check.sh"
  fi
}

usage() {
  cat <<USAGE
Использование:
  ./scripts/platform-maintenance.sh <command> [terragrunt args...]

Команды обновления:
  plan-k8s [terragrunt args]          terragrunt plan in test-cluster-k8s
  apply-k8s [terragrunt args]         terragrunt apply in test-cluster-k8s
  plan-argocd [terragrunt args]       terragrunt plan in argocd
  apply-argocd [terragrunt args]      terragrunt apply in argocd
  plan-vault-infra [terragrunt args]  terragrunt plan in vault-infra
  apply-vault-infra [terragrunt args] terragrunt apply in vault-infra

Команды проверки платформы:
  sync-gitops                         запустить Argo sync и дождаться готовности приложений
  upgrade-vault-observability         preflight + sync-gitops + vault test bootstrap + healthcheck
  upgrade-56                          устаревший алиас команды upgrade-vault-observability
  status                              запустить healthcheck-vault-observability.sh
  smoke-services                      запустить service-smoke-check.sh

Переменные окружения:
  LOAD_DOTENV=true                    подгружать k8s-box/.env перед выполнением команд
  AUTO_REFRESH_YC_TOKEN=true          обновлять TF_VAR_yc_token через yc iam create-token при возможности
  AUTO_FETCH_KUBECONFIG=true          обновлять kubeconfig до/после операций с кластером
  ARGOCD_NS=<namespace>               namespace ArgoCD (по умолчанию: argocd)
  WAIT_TIMEOUT_SEC=<seconds>          таймаут ожидания готовности приложений (по умолчанию: 600)
  AUTO_BOOTSTRAP_VAULT_TEST=true      запускать vault-test-bootstrap в upgrade-vault-observability
  ALLOW_VAULT_OUTOFSYNC_IN_TEST=true  разрешать vault OutOfSync/Healthy в test-профиле
  INFRA_REPO_DIR=<path>               путь к репозиторию infrastructure (по умолчанию: ../infrastructure)
  RUN_SMOKE_CHECK_AFTER_UPGRADE=true  запускать service smoke-check после upgrade-vault-observability

Установка/удаление стека перенесены в:
  ./scripts/bootstrap-k8s-box.sh apply|apply-cluster|destroy|destroy-cluster|recreate|recreate-cluster
USAGE
}

main() {
  load_local_env

  local cmd="${1:-}"
  case "${cmd}" in
    plan-all|apply-all|destroy-all|recreate-all) stack_commands_moved_to_bootstrap "${cmd}" ;;
    plan-k8s) shift; run_terragrunt "test-cluster-k8s" "plan" "$@" ;;
    apply-k8s) shift; run_terragrunt "test-cluster-k8s" "apply" "$@" ;;
    plan-argocd) shift; ensure_argocd_repo_auth; run_terragrunt "argocd" "plan" "$@" ;;
    apply-argocd) shift; ensure_cluster_context; ensure_argocd_repo_auth; run_terragrunt "argocd" "apply" "$@" ;;
    plan-vault-infra) shift; run_terragrunt "vault-infra" "plan" "$@" ;;
    apply-vault-infra) shift; run_terragrunt "vault-infra" "apply" "$@" ;;
    sync-gitops) sync_gitops_apps ;;
    upgrade-vault-observability) run_vault_observability_upgrade_flow ;;
    upgrade-56)
      warn "Команда 'upgrade-56' устарела, используйте 'upgrade-vault-observability'"
      run_vault_observability_upgrade_flow
      ;;
    status) "${SCRIPT_DIR}/healthcheck-vault-observability.sh" ;;
    smoke-services) "${SCRIPT_DIR}/service-smoke-check.sh" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
