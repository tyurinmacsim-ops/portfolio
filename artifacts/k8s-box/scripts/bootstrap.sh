#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-${ROOT_DIR}/../infrastructure}"

MODE="${1:-apply}"
LOAD_DOTENV="${LOAD_DOTENV:-true}"
AUTO_REFRESH_YC_TOKEN="${AUTO_REFRESH_YC_TOKEN:-true}"
MUTATE_REPO="true"
if [[ "$MODE" == "context" ]]; then
  MUTATE_REPO="false"
fi

log() {
  printf '[k8s-box] %s\n' "$*"
}

warn() {
  printf '[k8s-box][warn] %s\n' "$*" >&2
}

die() {
  printf '[k8s-box][error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Использование:
  ./scripts/bootstrap.sh [context|plan|apply]

Режимы:
  context  Определить значения из repo/TF config и записать .generated/bootstrap-context.{env,json}
  plan     context + terragrunt non-interactive plan
  apply    context + terragrunt non-interactive apply + post-bootstrap подстановки
USAGE
}

case "$MODE" in
  context|plan|apply) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    die "Неизвестный режим: $MODE"
    ;;
esac

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Требуется команда '$1'"
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

  log "Загружаю переменные из ${env_file}"
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a

  # Значения, уже экспортированные в runtime, должны иметь приоритет над .env,
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

sed_inplace() {
  local expr="$1"
  local file="$2"

  if sed --version >/dev/null 2>&1; then
    sed -i -E "$expr" "$file"
  else
    sed -i '' -E "$expr" "$file"
  fi
}

escape_sed_regex() {
  printf '%s' "$1" | sed -e 's/[][(){}.^$*+?|\\/]/\\&/g'
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

read_hcl_string() {
  local file="$1"
  local key="$2"

  [[ -f "$file" ]] || return 0

  awk -v key="$key" '
    $1 == key && $2 == "=" {
      if (match($0, /"[^"]*"/)) {
        value = substr($0, RSTART + 1, RLENGTH - 2)
        print value
        exit
      }
    }
  ' "$file"
}

set_hcl_string() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped

  [[ -f "$file" ]] || return 0

  escaped="$(escape_sed_replacement "$value")"
  sed_inplace "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*\").*(\"[[:space:]]*)$|\\1${escaped}\\2|" "$file"
}

replace_placeholder() {
  local file="$1"
  local placeholder="$2"
  local value="$3"
  local search
  local replace

  [[ -f "$file" ]] || return 0
  [[ -n "$value" ]] || return 0
  grep -qF "$placeholder" "$file" || return 0

  search="$(escape_sed_regex "$placeholder")"
  replace="$(escape_sed_replacement "$value")"
  sed_inplace "s|${search}|${replace}|g" "$file"
}

sanitize_slug() {
  local input="$1"
  local slug

  slug="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$slug" ]]; then
    slug="k8s-box"
  fi

  printf '%s' "$slug"
}

parse_gitlab_group_path() {
  local remote_url="$1"
  local path=""

  if [[ "$remote_url" =~ ^https?://[^/]+/(.+)$ ]]; then
    path="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ ^git@[^:]+:(.+)$ ]]; then
    path="${BASH_REMATCH[1]}"
  fi

  path="${path%.git}"
  if [[ "$path" == */* ]]; then
    printf '%s' "${path%/*}"
  fi
}

collect_default_storage_class() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 0
  fi

  kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n 1 || true
}

build_terragrunt_cmd() {
  local action="$1"
  local run_argocd="$2"

  require_cmd terragrunt

  local tg_help tg_run_help tg_run_all_help non_interactive_flag apply_mode
  tg_help="$(terragrunt --help 2>/dev/null || true)"
  tg_run_help="$(terragrunt run --help 2>/dev/null || true)"
  tg_run_all_help="$(terragrunt run-all --help 2>/dev/null || true)"

  if grep -q -- "--non-interactive" <<<"$tg_help"; then
    non_interactive_flag="--non-interactive"
  else
    non_interactive_flag="--terragrunt-non-interactive"
  fi

  if grep -q -- "--all" <<<"$tg_run_help"; then
    apply_mode="modern"
  else
    apply_mode="legacy"
  fi

  if [[ "$apply_mode" == "modern" ]]; then
    TERRAGRUNT_CMD=(terragrunt "$non_interactive_flag" run --all)

    if [[ "$run_argocd" == "false" ]]; then
      TERRAGRUNT_CMD+=(--queue-exclude-dir "$ROOT_DIR/argocd")
    fi

    case "$action" in
      plan)
        TERRAGRUNT_CMD+=(-- plan -input=false)
        ;;
      apply)
        TERRAGRUNT_CMD+=(-- apply -auto-approve -input=false)
        ;;
      *)
        die "Неподдерживаемое действие terragrunt: $action"
        ;;
    esac
  else
    case "$action" in
      plan)
        TERRAGRUNT_CMD=(terragrunt "$non_interactive_flag" run-all plan -input=false)
        ;;
      apply)
        TERRAGRUNT_CMD=(terragrunt "$non_interactive_flag" run-all apply --auto-approve -input=false)
        ;;
      *)
        die "Неподдерживаемое действие terragrunt: $action"
        ;;
    esac

    if [[ "$run_argocd" == "false" ]]; then
      if grep -q -- "--terragrunt-exclude-dir" <<<"$tg_run_all_help"; then
        TERRAGRUNT_CMD+=(--terragrunt-exclude-dir "$ROOT_DIR/argocd")
      else
        warn "В legacy Terragrunt нельзя исключить argocd через --terragrunt-exclude-dir"
      fi
    fi
  fi
}

ensure_yc_token() {
  if [[ -z "${TF_VAR_yc_token:-}" && -n "${TF_VAR_YC_TOKEN:-}" ]]; then
    export TF_VAR_yc_token="${TF_VAR_YC_TOKEN}"
    log "TF_VAR_yc_token взят из TF_VAR_YC_TOKEN"
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
      log "Использую свежий TF_VAR_yc_token из yc iam create-token"
      return 0
    fi
    warn "Не удалось обновить IAM token через yc, пробую TF_VAR_yc_token/YC_TOKEN"
  fi

  if [[ -n "${TF_VAR_yc_token:-}" ]]; then
    log "Использую TF_VAR_yc_token из окружения"
    return 0
  fi

  if [[ -n "${YC_TOKEN:-}" ]]; then
    export TF_VAR_YC_TOKEN="$YC_TOKEN"
    export TF_VAR_yc_token="$YC_TOKEN"
    log "TF_VAR_yc_token взят из YC_TOKEN"
    return 0
  fi

  local generated_token
  generated_token="$(yc iam create-token 2>/dev/null || true)"
  if [[ -n "$generated_token" ]]; then
    export TF_VAR_YC_TOKEN="$generated_token"
    export TF_VAR_yc_token="$generated_token"
    log "Сгенерирован IAM токен через yc iam create-token"
    return 0
  fi

  die "Нужен TF_VAR_YC_TOKEN/TF_VAR_yc_token (или YC_TOKEN), иначе Terraform не авторизуется в Yandex Cloud"
}

ensure_argocd_repo_auth() {
  if [[ -z "${K8S_BOX_GITLAB_REPO_TOKEN:-}" && -n "${GITLAB_TOKEN:-}" ]]; then
    export K8S_BOX_GITLAB_REPO_TOKEN="${GITLAB_TOKEN}"
  fi

  [[ -n "${K8S_BOX_GITLAB_REPO_TOKEN:-}" ]]
}

require_cmd awk
require_cmd git
require_cmd sed
load_local_env

ENV_FILE="$ROOT_DIR/env.hcl"
ARGOCD_FILE="$ROOT_DIR/argocd/terragrunt.hcl"
CLUSTER_FILE="$ROOT_DIR/test-cluster-k8s/terragrunt.hcl"
VAULT_FILE="$ROOT_DIR/vault-infra/terragrunt.hcl"
GENERATED_DIR="$ROOT_DIR/.generated"
CONTEXT_ENV_FILE="$GENERATED_DIR/bootstrap-context.env"
CONTEXT_JSON_FILE="$GENERATED_DIR/bootstrap-context.json"
RUNTIME_ENV_FILE="$GENERATED_DIR/bootstrap-runtime.env"

[[ -f "$ENV_FILE" ]] || die "Не найден env.hcl"
[[ -f "$CLUSTER_FILE" ]] || die "Не найден test-cluster-k8s/terragrunt.hcl"

cloud_id="$(read_hcl_string "$ENV_FILE" "cloud_id" || true)"
if [[ -z "$cloud_id" || "$cloud_id" == "string" ]]; then
  cloud_id="${YC_CLOUD_ID:-}"
fi
if [[ -z "$cloud_id" && "${MODE}" != "context" ]]; then
  if command -v yc >/dev/null 2>&1; then
    cloud_id="$(yc config get cloud-id 2>/dev/null || true)"
  fi
fi

folder_name="$(read_hcl_string "$ENV_FILE" "folder_name" || true)"
network_name="$(read_hcl_string "$ENV_FILE" "network_name" || true)"
yc_zone="$(read_hcl_string "$ENV_FILE" "yc_zone" || true)"

cluster_name="${K8S_BOX_CLUSTER_NAME:-$(read_hcl_string "$CLUSTER_FILE" "name" || true)}"
cluster_version="${K8S_BOX_CLUSTER_VERSION:-$(read_hcl_string "$CLUSTER_FILE" "cluster_version" || true)}"
if [[ -z "${cluster_version}" ]]; then
  cluster_version="$(read_hcl_string "$CLUSTER_FILE" "master_version" || true)"
fi

vault_kms_key_name="${K8S_BOX_VAULT_KMS_KEY_NAME:-$(read_hcl_string "$VAULT_FILE" "kms_key_name" || true)}"
vault_kms_sa_name="${K8S_BOX_VAULT_KMS_SA_NAME:-$(read_hcl_string "$VAULT_FILE" "vault_kms_sa_name" || true)}"

if [[ -z "$folder_name" || "$folder_name" == "имя каталога в ЯО" ]]; then
  folder_name="$(sanitize_slug "$(basename "$ROOT_DIR")")"
  if [[ "$MUTATE_REPO" == "true" ]]; then
    set_hcl_string "$ENV_FILE" "folder_name" "$folder_name"
  fi
fi

if [[ -z "$network_name" || "$network_name" == "string" ]]; then
  network_name="k8s-vpc-01"
  if [[ "$MUTATE_REPO" == "true" ]]; then
    set_hcl_string "$ENV_FILE" "network_name" "$network_name"
  fi
fi

if [[ -n "$cloud_id" ]]; then
  if [[ "$MUTATE_REPO" == "true" ]]; then
    set_hcl_string "$ENV_FILE" "cloud_id" "$cloud_id"
  fi
fi

if [[ -z "$cluster_name" ]]; then
  cluster_name="test-cluster"
fi
if [[ -z "$cluster_version" ]]; then
  cluster_version="1.33"
fi

if [[ -z "${K8S_BOX_GITLAB_SUBGROUP:-}" ]]; then
  export K8S_BOX_GITLAB_SUBGROUP="$(sanitize_slug "$cluster_name")"
fi

remote_url="$(git -C "$ROOT_DIR" config --get remote.origin.url 2>/dev/null || true)"
if [[ -z "${K8S_BOX_GITLAB_GROUP_PATH:-}" && "$remote_url" == *gitlab* ]]; then
  detected_group_path="$(parse_gitlab_group_path "$remote_url")"
  if [[ -n "$detected_group_path" ]]; then
    export K8S_BOX_GITLAB_GROUP_PATH="$detected_group_path"
  fi
fi

default_storage_class="$(collect_default_storage_class)"

mkdir -p "$GENERATED_DIR"
chmod 700 "$GENERATED_DIR"

cat > "$CONTEXT_ENV_FILE" <<ENV
# Generated by scripts/bootstrap.sh
CLOUD_ID="${cloud_id}"
YC_ZONE="${yc_zone}"
NETWORK_NAME="${network_name}"
FOLDER_NAME="${folder_name}"
CLUSTER_NAME="${cluster_name}"
CLUSTER_VERSION="${cluster_version}"
VAULT_KMS_KEY_NAME="${vault_kms_key_name}"
VAULT_KMS_SA_NAME="${vault_kms_sa_name}"
DEFAULT_STORAGE_CLASS="${default_storage_class}"
GIT_REMOTE_URL="${remote_url}"
K8S_BOX_GITLAB_GROUP_PATH="${K8S_BOX_GITLAB_GROUP_PATH:-}"
K8S_BOX_GITLAB_SUBGROUP="${K8S_BOX_GITLAB_SUBGROUP:-}"
ENV
chmod 600 "$CONTEXT_ENV_FILE"

cat > "$CONTEXT_JSON_FILE" <<JSON
{
  "cloud_id": "${cloud_id}",
  "yc_zone": "${yc_zone}",
  "network_name": "${network_name}",
  "folder_name": "${folder_name}",
  "cluster_name": "${cluster_name}",
  "cluster_version": "${cluster_version}",
  "vault_kms_key_name": "${vault_kms_key_name}",
  "vault_kms_sa_name": "${vault_kms_sa_name}",
  "default_storage_class": "${default_storage_class}",
  "git_remote_url": "${remote_url}",
  "gitlab_group_path": "${K8S_BOX_GITLAB_GROUP_PATH:-}",
  "gitlab_subgroup": "${K8S_BOX_GITLAB_SUBGROUP:-}"
}
JSON
chmod 600 "$CONTEXT_JSON_FILE"

if [[ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    export ARGOCD_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
  else
    export ARGOCD_ADMIN_PASSWORD="$(date +%s)-$(sanitize_slug "$cluster_name")"
    warn "openssl не найден, сгенерирован упрощенный пароль для ArgoCD"
  fi
fi

cat > "$RUNTIME_ENV_FILE" <<RUNTIME
# Generated by scripts/bootstrap.sh
export K8S_BOX_GITLAB_GROUP_PATH="${K8S_BOX_GITLAB_GROUP_PATH:-}"
export K8S_BOX_GITLAB_SUBGROUP="${K8S_BOX_GITLAB_SUBGROUP:-}"
export ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"
RUNTIME
chmod 600 "$RUNTIME_ENV_FILE"

log "Контекст сохранен: $CONTEXT_ENV_FILE"
log "Контекст сохранен: $CONTEXT_JSON_FILE"

if [[ "$MODE" == "context" ]]; then
  exit 0
fi

ensure_yc_token
require_cmd terraform

run_argocd=true
if [[ ! -f "$ARGOCD_FILE" ]]; then
  run_argocd=false
  warn "argocd/terragrunt.hcl не найден, модуль argocd будет пропущен"
fi
if [[ -z "${K8S_BOX_GITLAB_GROUP_PATH:-}" ]]; then
  run_argocd=false
  warn "Не определен K8S_BOX_GITLAB_GROUP_PATH, модуль argocd будет пропущен"
fi
if ! ensure_argocd_repo_auth && [[ -z "${TF_VAR_gitlab_token:-}" ]]; then
  run_argocd=false
  warn "Не задан K8S_BOX_GITLAB_REPO_TOKEN (или GITLAB_TOKEN), модуль argocd будет пропущен"
fi

build_terragrunt_cmd "$MODE" "$run_argocd"
log "Запуск: ${TERRAGRUNT_CMD[*]}"
"${TERRAGRUNT_CMD[@]}"

if [[ "$MODE" == "plan" ]]; then
  exit 0
fi

cluster_id="$(cd "$ROOT_DIR/test-cluster-k8s" && terragrunt output -raw cluster_id 2>/dev/null || true)"
if [[ -n "$cluster_id" ]]; then
  log "Обновляю kubeconfig для cluster_id=${cluster_id}"
  yc managed-kubernetes cluster get-credentials --id "$cluster_id" --external >/dev/null 2>&1 || warn "Не удалось автоматически обновить kubeconfig"
fi

if [[ -z "$default_storage_class" ]]; then
  default_storage_class="$(collect_default_storage_class)"
fi

vault_kms_key_id="$(cd "$ROOT_DIR/vault-infra" && terragrunt output -raw vault_unseal_kms_key_id 2>/dev/null || true)"
vault_backup_bucket="$(cd "$ROOT_DIR/vault-infra" && terragrunt output -raw vault_backup_bucket_name 2>/dev/null || true)"

vault_base_values="${INFRA_REPO_DIR}/vault/manifests/values-ha-raft.yaml"
vault_backup_manifest="${INFRA_REPO_DIR}/vault/manifests/backup/backup-cronjob.yaml"
obs_vm_values="${INFRA_REPO_DIR}/observability/manifests/victoria/victoria-metrics-k8s-stack.values.yaml"
obs_loki_values="${INFRA_REPO_DIR}/observability/manifests/loki/loki.values.yaml"

replace_placeholder "$vault_base_values" "<CHANGE_ME_KMS_KEY_ID>" "$vault_kms_key_id"
replace_placeholder "$vault_backup_manifest" "<CHANGE_ME_BACKUP_BUCKET>" "$vault_backup_bucket"

if [[ -n "$default_storage_class" ]]; then
  replace_placeholder "$obs_vm_values" "CHANGE_ME_STORAGE_CLASS" "$default_storage_class"
  replace_placeholder "$obs_loki_values" "CHANGE_ME_STORAGE_CLASS" "$default_storage_class"
fi

replace_placeholder "$obs_vm_values" "CHANGE_ME_CLUSTER_NAME" "$cluster_name"

log "Готово. Runtime-переменные: $RUNTIME_ENV_FILE"
if [[ "$run_argocd" == false ]]; then
  warn "ArgoCD пропущен. Для включения задай K8S_BOX_GITLAB_REPO_TOKEN (или GITLAB_TOKEN) и K8S_BOX_GITLAB_GROUP_PATH (или remote.origin на GitLab)."
fi
