#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REQ_FILE=""
OUTPUT_DIR=""
FORCE="false"
VALIDATE_ONLY="false"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Использование:
  ./scripts/scaffold-stack-from-requirements.sh --requirements <file> [--output <dir>] [--force] [--validate-only]

Назначение:
  Создать отдельный Terragrunt-стек (отдельный state) из бизнес/тех требований.
  Terraform-модули остаются общими; копируется и параметризуется только live-слой Terragrunt.

Примеры:
  ./scripts/scaffold-stack-from-requirements.sh \
    --requirements ./profiles/cluster-requirements.example.env \
    --output ../k8s-box-acme-prod

  ./scripts/scaffold-stack-from-requirements.sh \
    --requirements ./profiles/acme-prod.env \
    --output ./stacks/acme-prod \
    --force

  ./scripts/scaffold-stack-from-requirements.sh \
    --requirements ./profiles/acme-prod.env \
    --validate-only
USAGE
}

ceil_div() {
  local numerator="$1"
  local denominator="$2"
  awk -v n="$numerator" -v d="$denominator" 'BEGIN {
    if (d <= 0) { print 0; exit }
    print int((n + d - 1) / d)
  }'
}

max3() {
  local a="$1" b="$2" c="$3"
  awk -v a="$a" -v b="$b" -v c="$c" 'BEGIN {
    m=a; if (b>m) m=b; if (c>m) m=c; print m
  }'
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

to_hcl_list() {
  local csv="${1:-}"
  local out=""
  local item trimmed

  IFS=',' read -r -a _parts <<< "${csv}"
  for item in "${_parts[@]}"; do
    trimmed="$(printf '%s' "${item}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "${trimmed}" ]] || continue
    if [[ -n "${out}" ]]; then
      out+=", "
    fi
    out+="\"${trimmed}\""
  done

  # Преобразуем CSV в HCL-список строк: "a,b" -> ["a", "b"].
  printf '[%s]' "${out}"
}

normalize_bool() {
  local name="$1"
  local value="${2:-}"
  local normalized
  normalized="$(to_lower "${value}")"
  case "${normalized}" in
    true|1|yes) printf 'true'; return 0 ;;
    false|0|no) printf 'false'; return 0 ;;
    *) fail "Некорректное булево значение для ${name}: ${value} (ожидается true/false)" ;;
  esac
}

require_int() {
  local name="$1"
  local value="${2:-}"
  [[ "${value}" =~ ^[0-9]+$ ]] || fail "Переменная ${name} должна быть целым числом, получено: ${value}"
}

require_nonempty_safe_string() {
  local name="$1"
  local value="${2:-}"
  [[ -n "${value}" ]] || fail "Переменная ${name} пустая"
  [[ "${value}" != *$'\n'* ]] || fail "Переменная ${name} содержит перевод строки, это не поддерживается"
  [[ "${value}" != *"\""* ]] || fail "Переменная ${name} содержит '\"', это не поддерживается"
}

require_var() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "${value}" ]] || fail "В requirements отсутствует обязательная переменная: ${name}"
  [[ "${value}" != *"CHANGE_ME"* ]] || fail "В переменной ${name} остался плейсхолдер: ${value}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --requirements|-r)
      REQ_FILE="${2:-}"
      shift 2
      ;;
    --output|-o)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY="true"
      shift
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

[[ -n "${REQ_FILE}" ]] || fail "Pass --requirements <file>"
[[ -f "${REQ_FILE}" ]] || fail "Не найден файл requirements: ${REQ_FILE}"

set -a
# shellcheck disable=SC1090
source "${REQ_FILE}"
set +a

require_var "STACK_NAME"
require_var "CLOUD_ID"
require_var "YC_ZONE"
require_var "FOLDER_NAME"
require_var "NETWORK_NAME"
require_var "CLUSTER_NAME"
require_var "SUBNET_CIDR"
require_var "ESTIMATED_APP_PODS"
require_var "AVG_POD_CPU_M"
require_var "AVG_POD_MEM_MIB"
require_var "K8S_BOX_GITLAB_API_URL"
require_var "K8S_BOX_GITLAB_GROUP_PATH"
require_var "K8S_BOX_GITLAB_SUBGROUP"
require_var "K8S_BOX_STATIC_GIT_REPO_BASE_URL"
require_var "K8S_BOX_GITLAB_REPO_USER"

CLUSTER_VERSION="${CLUSTER_VERSION:-1.33}"
PUBLIC_ACCESS="${PUBLIC_ACCESS:-true}"
SYSTEM_RESERVE_PCT="${SYSTEM_RESERVE_PCT:-30}"
CPU_UTIL_TARGET_PCT="${CPU_UTIL_TARGET_PCT:-70}"
MEM_UTIL_TARGET_PCT="${MEM_UTIL_TARGET_PCT:-75}"
NODE_VCPU="${NODE_VCPU:-4}"
NODE_MEMORY_GIB="${NODE_MEMORY_GIB:-16}"
NODE_BOOT_DISK_GB="${NODE_BOOT_DISK_GB:-64}"
WORKER_MIN="${WORKER_MIN:-2}"
WORKER_MAX="${WORKER_MAX:-10}"
ENABLE_MONITORING_NODE="${ENABLE_MONITORING_NODE:-true}"
MONITORING_MIN="${MONITORING_MIN:-1}"
MONITORING_MAX="${MONITORING_MAX:-2}"
MONITORING_INITIAL="${MONITORING_INITIAL:-1}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
KMS_KEY_ROTATION_PERIOD="${KMS_KEY_ROTATION_PERIOD:-2160h}"
CREATE_BACKUP_BUCKET="${CREATE_BACKUP_BUCKET:-true}"
BACKUP_BUCKET_NAME="${BACKUP_BUCKET_NAME:-}"
OBSERVABILITY_STACK="${OBSERVABILITY_STACK:-vm-loki-grafana}"
OBSERVABILITY_PROFILE="${OBSERVABILITY_PROFILE:-}"
OBSERVABILITY_SECRET_PROVIDER="${OBSERVABILITY_SECRET_PROVIDER:-vso}"
OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST="${OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST:-false}"
VAULT_PROFILE="${VAULT_PROFILE:-}"
VAULT_ENABLE_BACKUP_MANIFESTS="${VAULT_ENABLE_BACKUP_MANIFESTS:-true}"
VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST="${VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST:-false}"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-STABLE}"
CNI_TYPE="${CNI_TYPE:-calico}"
ALLOW_PUBLIC_LOAD_BALANCERS="${ALLOW_PUBLIC_LOAD_BALANCERS:-$([[ "${ENVIRONMENT}" == "test" ]] && printf 'false' || printf 'true')}"
MASTER_AUTO_UPGRADE="${MASTER_AUTO_UPGRADE:-false}"
MASTER_PUBLIC_ACCESS="${MASTER_PUBLIC_ACCESS:-${PUBLIC_ACCESS}}"
API_ALLOWED_CIDRS="${API_ALLOWED_CIDRS:-0.0.0.0/0}"
SSH_ALLOWED_CIDRS="${SSH_ALLOWED_CIDRS:-${SUBNET_CIDR}}"
ENABLE_NLB_HC_RULE="${ENABLE_NLB_HC_RULE:-$([[ "${ENVIRONMENT}" == "test" ]] && printf 'false' || printf 'true')}"
ENABLE_NODEPORT_RULE="${ENABLE_NODEPORT_RULE:-true}"
NODEPORT_ALLOWED_CIDRS="${NODEPORT_ALLOWED_CIDRS:-${API_ALLOWED_CIDRS}}"
NODEPORT_FROM="${NODEPORT_FROM:-30000}"
NODEPORT_TO="${NODEPORT_TO:-32767}"

PUBLIC_ACCESS="$(normalize_bool "PUBLIC_ACCESS" "${PUBLIC_ACCESS}")"
ENABLE_MONITORING_NODE="$(normalize_bool "ENABLE_MONITORING_NODE" "${ENABLE_MONITORING_NODE}")"
CREATE_BACKUP_BUCKET="$(normalize_bool "CREATE_BACKUP_BUCKET" "${CREATE_BACKUP_BUCKET}")"
MASTER_AUTO_UPGRADE="$(normalize_bool "MASTER_AUTO_UPGRADE" "${MASTER_AUTO_UPGRADE}")"
MASTER_PUBLIC_ACCESS="$(normalize_bool "MASTER_PUBLIC_ACCESS" "${MASTER_PUBLIC_ACCESS}")"
ALLOW_PUBLIC_LOAD_BALANCERS="$(normalize_bool "ALLOW_PUBLIC_LOAD_BALANCERS" "${ALLOW_PUBLIC_LOAD_BALANCERS}")"
ENABLE_NLB_HC_RULE="$(normalize_bool "ENABLE_NLB_HC_RULE" "${ENABLE_NLB_HC_RULE}")"
ENABLE_NODEPORT_RULE="$(normalize_bool "ENABLE_NODEPORT_RULE" "${ENABLE_NODEPORT_RULE}")"

require_nonempty_safe_string "STACK_NAME" "${STACK_NAME}"
require_nonempty_safe_string "CLOUD_ID" "${CLOUD_ID}"
require_nonempty_safe_string "YC_ZONE" "${YC_ZONE}"
require_nonempty_safe_string "FOLDER_NAME" "${FOLDER_NAME}"
require_nonempty_safe_string "NETWORK_NAME" "${NETWORK_NAME}"
require_nonempty_safe_string "CLUSTER_NAME" "${CLUSTER_NAME}"
require_nonempty_safe_string "SUBNET_CIDR" "${SUBNET_CIDR}"
require_nonempty_safe_string "K8S_BOX_GITLAB_API_URL" "${K8S_BOX_GITLAB_API_URL}"
require_nonempty_safe_string "K8S_BOX_GITLAB_GROUP_PATH" "${K8S_BOX_GITLAB_GROUP_PATH}"
require_nonempty_safe_string "K8S_BOX_GITLAB_SUBGROUP" "${K8S_BOX_GITLAB_SUBGROUP}"
require_nonempty_safe_string "K8S_BOX_STATIC_GIT_REPO_BASE_URL" "${K8S_BOX_STATIC_GIT_REPO_BASE_URL}"
require_nonempty_safe_string "K8S_BOX_GITLAB_REPO_USER" "${K8S_BOX_GITLAB_REPO_USER}"

require_int "ESTIMATED_APP_PODS" "${ESTIMATED_APP_PODS}"
require_int "AVG_POD_CPU_M" "${AVG_POD_CPU_M}"
require_int "AVG_POD_MEM_MIB" "${AVG_POD_MEM_MIB}"
require_int "SYSTEM_RESERVE_PCT" "${SYSTEM_RESERVE_PCT}"
require_int "CPU_UTIL_TARGET_PCT" "${CPU_UTIL_TARGET_PCT}"
require_int "MEM_UTIL_TARGET_PCT" "${MEM_UTIL_TARGET_PCT}"
require_int "NODE_VCPU" "${NODE_VCPU}"
require_int "NODE_MEMORY_GIB" "${NODE_MEMORY_GIB}"
require_int "NODE_BOOT_DISK_GB" "${NODE_BOOT_DISK_GB}"
require_int "WORKER_MIN" "${WORKER_MIN}"
require_int "WORKER_MAX" "${WORKER_MAX}"
require_int "MONITORING_MIN" "${MONITORING_MIN}"
require_int "MONITORING_MAX" "${MONITORING_MAX}"
require_int "MONITORING_INITIAL" "${MONITORING_INITIAL}"
require_int "NODEPORT_FROM" "${NODEPORT_FROM}"
require_int "NODEPORT_TO" "${NODEPORT_TO}"

if (( WORKER_MIN < 1 )); then
  fail "WORKER_MIN must be >= 1"
fi
if (( WORKER_MAX < WORKER_MIN )); then
  fail "WORKER_MAX must be >= WORKER_MIN"
fi
if (( CPU_UTIL_TARGET_PCT < 30 || CPU_UTIL_TARGET_PCT > 95 )); then
  fail "CPU_UTIL_TARGET_PCT must be in 30..95"
fi
if (( MEM_UTIL_TARGET_PCT < 30 || MEM_UTIL_TARGET_PCT > 95 )); then
  fail "MEM_UTIL_TARGET_PCT must be in 30..95"
fi
if (( SYSTEM_RESERVE_PCT < 5 || SYSTEM_RESERVE_PCT > 100 )); then
  fail "SYSTEM_RESERVE_PCT must be in 5..100"
fi
if [[ "${ENABLE_MONITORING_NODE}" == "false" ]]; then
  MONITORING_MIN=0
  MONITORING_MAX=0
  MONITORING_INITIAL=0
elif (( MONITORING_MAX < MONITORING_MIN )); then
  fail "MONITORING_MAX must be >= MONITORING_MIN"
elif (( MONITORING_INITIAL < MONITORING_MIN || MONITORING_INITIAL > MONITORING_MAX )); then
  fail "MONITORING_INITIAL must be in [MONITORING_MIN..MONITORING_MAX]"
fi

if [[ "${CREATE_BACKUP_BUCKET}" == "true" && -z "${BACKUP_BUCKET_NAME}" ]]; then
  fail "BACKUP_BUCKET_NAME is required when CREATE_BACKUP_BUCKET=true"
fi

case "${OBSERVABILITY_STACK}" in
  vm-loki-grafana|prom-loki-grafana) ;;
  *) fail "OBSERVABILITY_STACK must be vm-loki-grafana or prom-loki-grafana" ;;
esac

if [[ -z "${OBSERVABILITY_PROFILE}" ]]; then
  if [[ "${ENVIRONMENT}" == "prod" ]]; then
    OBSERVABILITY_PROFILE="prod"
  else
    OBSERVABILITY_PROFILE="test"
  fi
fi
if [[ -z "${VAULT_PROFILE}" ]]; then
  if [[ "${ENVIRONMENT}" == "prod" ]]; then
    VAULT_PROFILE="prod"
  else
    VAULT_PROFILE="test"
  fi
fi
case "${OBSERVABILITY_PROFILE}" in
  test|dev|prod) ;;
  *) fail "OBSERVABILITY_PROFILE must be test|dev|prod" ;;
esac
case "${VAULT_PROFILE}" in
  test|prod) ;;
  *) fail "VAULT_PROFILE must be test|prod" ;;
esac

case "${OBSERVABILITY_SECRET_PROVIDER}" in
  vso|external-secrets|manual) ;;
  *) fail "OBSERVABILITY_SECRET_PROVIDER must be vso|external-secrets|manual" ;;
esac
case "${OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST}" in
  true|false) ;;
  *) fail "OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST must be true|false" ;;
esac
case "${VAULT_ENABLE_BACKUP_MANIFESTS}" in
  true|false) ;;
  *) fail "VAULT_ENABLE_BACKUP_MANIFESTS must be true|false" ;;
esac
case "${VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST}" in
  true|false) ;;
  *) fail "VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST must be true|false" ;;
esac

case "${RELEASE_CHANNEL}" in
  RAPID|REGULAR|STABLE) ;;
  *) fail "RELEASE_CHANNEL must be RAPID|REGULAR|STABLE" ;;
esac

case "${CNI_TYPE}" in
  calico|cilium) ;;
  *) fail "CNI_TYPE must be calico|cilium" ;;
esac

if (( NODEPORT_TO < NODEPORT_FROM )); then
  fail "NODEPORT_TO must be >= NODEPORT_FROM"
fi

if [[ "${CNI_TYPE}" == "cilium" ]]; then
  ENABLE_CILIUM_POLICY="true"
else
  ENABLE_CILIUM_POLICY="false"
fi

api_allowed_cidrs_hcl="$(to_hcl_list "${API_ALLOWED_CIDRS}")"
ssh_allowed_cidrs_hcl="$(to_hcl_list "${SSH_ALLOWED_CIDRS}")"
nodeport_allowed_cidrs_hcl="$(to_hcl_list "${NODEPORT_ALLOWED_CIDRS}")"

# Расчет стартового размера worker-группы по входной pod-нагрузке.
cpu_needed_m="$(awk -v p="${ESTIMATED_APP_PODS}" -v c="${AVG_POD_CPU_M}" -v r="${SYSTEM_RESERVE_PCT}" 'BEGIN { print int((p*c*(100+r)+99)/100) }')"
mem_needed_mib="$(awk -v p="${ESTIMATED_APP_PODS}" -v m="${AVG_POD_MEM_MIB}" -v r="${SYSTEM_RESERVE_PCT}" 'BEGIN { print int((p*m*(100+r)+99)/100) }')"

cpu_capacity_per_node_m="$(awk -v v="${NODE_VCPU}" -v u="${CPU_UTIL_TARGET_PCT}" 'BEGIN { print int(v*1000*u/100) }')"
mem_capacity_per_node_mib="$(awk -v g="${NODE_MEMORY_GIB}" -v u="${MEM_UTIL_TARGET_PCT}" 'BEGIN { print int(g*1024*u/100) }')"

cpu_nodes="$(ceil_div "${cpu_needed_m}" "${cpu_capacity_per_node_m}")"
mem_nodes="$(ceil_div "${mem_needed_mib}" "${mem_capacity_per_node_mib}")"
worker_initial="$(max3 "${cpu_nodes}" "${mem_nodes}" "${WORKER_MIN}")"
if (( worker_initial > WORKER_MAX )); then
  warn "Calculated worker_initial=${worker_initial} > WORKER_MAX=${WORKER_MAX}; clamping to WORKER_MAX"
  worker_initial="${WORKER_MAX}"
fi

info "Calculated sizing:"
info "  cpu_needed_m=${cpu_needed_m}, mem_needed_mib=${mem_needed_mib}"
info "  cpu_nodes=${cpu_nodes}, mem_nodes=${mem_nodes}, worker_initial=${worker_initial}"

if [[ "${ENVIRONMENT}" == "test" ]]; then
  [[ "${ALLOW_PUBLIC_LOAD_BALANCERS}" == "false" ]] || warn "Для test рекомендуется ALLOW_PUBLIC_LOAD_BALANCERS=false"
  [[ "${ENABLE_NLB_HC_RULE}" == "false" ]] || warn "Для test рекомендуется ENABLE_NLB_HC_RULE=false"
fi

if [[ "${ENVIRONMENT}" == "prod" ]]; then
  (( WORKER_MIN >= 2 )) || warn "Для prod рекомендуется WORKER_MIN >= 2"
  [[ "${ENABLE_MONITORING_NODE}" == "true" ]] || warn "Для prod рекомендуется ENABLE_MONITORING_NODE=true"
fi

if [[ "${VALIDATE_ONLY}" == "true" ]]; then
  printf '\n[SUMMARY] Проверка requirements завершена\n'
  printf '  STACK_NAME=%s\n' "${STACK_NAME}"
  printf '  ENVIRONMENT=%s\n' "${ENVIRONMENT}"
  printf '  CLUSTER_NAME=%s\n' "${CLUSTER_NAME}"
  printf '  CLUSTER_VERSION=%s\n' "${CLUSTER_VERSION}"
  printf '  RELEASE_CHANNEL=%s\n' "${RELEASE_CHANNEL}"
  printf '  CNI_TYPE=%s\n' "${CNI_TYPE}"
  printf '  MASTER_PUBLIC_ACCESS=%s\n' "${MASTER_PUBLIC_ACCESS}"
  printf '  ALLOW_PUBLIC_LOAD_BALANCERS=%s\n' "${ALLOW_PUBLIC_LOAD_BALANCERS}"
  printf '  ENABLE_MONITORING_NODE=%s\n' "${ENABLE_MONITORING_NODE}"
  printf '  WORKER_MIN=%s WORKER_MAX=%s WORKER_INITIAL=%s\n' "${WORKER_MIN}" "${WORKER_MAX}" "${worker_initial}"
  printf '  OBSERVABILITY_STACK=%s (%s)\n' "${OBSERVABILITY_STACK}" "${OBSERVABILITY_PROFILE}"
  printf '  VAULT_PROFILE=%s\n' "${VAULT_PROFILE}"
  exit 0
fi

if [[ -z "${OUTPUT_DIR}" ]]; then
  OUTPUT_DIR="${ROOT_DIR}/stacks/${STACK_NAME}"
fi

if [[ -e "${OUTPUT_DIR}" && "${FORCE}" != "true" ]]; then
  fail "Output already exists: ${OUTPUT_DIR} (use --force to overwrite)"
fi

if [[ -e "${OUTPUT_DIR}" && "${FORCE}" == "true" ]]; then
  rm -rf "${OUTPUT_DIR}"
fi

info "Copying base stack to ${OUTPUT_DIR}"
rsync -a "${ROOT_DIR}/" "${OUTPUT_DIR}/" \
  --exclude .git \
  --exclude .env \
  --exclude .terragrunt-cache \
  --exclude .terraform \
  --exclude .generated \
  --exclude stacks \
  --exclude '*.tfstate' \
  --exclude '*.tfstate.*'

cat > "${OUTPUT_DIR}/env.hcl" <<EOF
locals {
  cloud_id     = "${CLOUD_ID}"
  yc_zone      = "${YC_ZONE}"
  network_name = "${NETWORK_NAME}"
  folder_name  = "${FOLDER_NAME}"
}
EOF

cat > "${OUTPUT_DIR}/vpc/terragrunt.hcl" <<EOF
terraform {
  source = "../yc-vpc-module"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "b1g00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF_PROVIDER
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
EOF_PROVIDER
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  folder_id    = dependency.folder.outputs.folder_id
  network_name = local.env_vars.locals.network_name
  cloud_id     = local.env_vars.locals.cloud_id

  private_subnets = [
    {
      v4_cidr_blocks = ["${SUBNET_CIDR}"]
      zone           = "${YC_ZONE}"
    }
  ]

  create_nat_gw = true
}
EOF

nodeport_rule=""
nodeport_rule_comma=""
if [[ "${ENABLE_NODEPORT_RULE}" == "true" ]]; then
  nodeport_rule_comma=","
  nodeport_rule=$(cat <<EOF
    {
      description    = "NodePort range access"
      protocol       = "TCP"
      from_port      = ${NODEPORT_FROM}
      to_port        = ${NODEPORT_TO}
      v4_cidr_blocks = ${nodeport_allowed_cidrs_hcl}
    }
EOF
)
fi

cat > "${OUTPUT_DIR}/security-group/terragrunt.hcl" <<EOF
terraform {
  source = "../yc-security-group-module"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "b1g00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id = "enp00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF_PROVIDER
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
EOF_PROVIDER
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  network_id = dependency.vpc.outputs.vpc_id
  folder_id  = dependency.folder.outputs.folder_id
  cloud_id   = local.env_vars.locals.cloud_id

  name        = "k8s-cluster-sg"
  description = "Security group for Kubernetes cluster nodes"
  self        = true
  nlb_hc      = true

  ingress_rules_with_cidrs = [
    {
      description    = "K8s pod/service intra-cluster traffic"
      protocol       = "ANY"
      from_port      = 0
      to_port        = 65535
      v4_cidr_blocks = ["172.19.0.0/16", "172.20.0.0/16"]
    },
    {
      description    = "SSH from internal network"
      protocol       = "TCP"
      port           = 22
      v4_cidr_blocks = ${ssh_allowed_cidrs_hcl}
    },
    {
      description    = "Kubernetes API server"
      protocol       = "TCP"
      port           = 443
      v4_cidr_blocks = ${api_allowed_cidrs_hcl}
    }${nodeport_rule_comma}
${nodeport_rule}
  ]

  egress_rules = [
    {
      description    = "All outbound traffic via NAT"
      protocol       = "ANY"
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}
EOF

monitoring_group=""
if [[ "${ENABLE_MONITORING_NODE}" == "true" ]]; then
  monitoring_group=$(cat <<EOF
    "prod-k8s-ng-monitoring" = {
      description = "Monitoring nodes group"
      auto_scale = {
        min     = ${MONITORING_MIN}
        max     = ${MONITORING_MAX}
        initial = ${MONITORING_INITIAL}
      }
      boot_disk_size = ${NODE_BOOT_DISK_GB}
      node_locations = [
        {
          zone      = "${YC_ZONE}"
          subnet_id = dependency.vpc.outputs.private_subnets["${SUBNET_CIDR}"].subnet_id
        }
      ]
      node_labels = {
        role            = "monitoring"
        environment     = "${ENVIRONMENT}"
        monitoring-node = "true"
      }
      max_expansion   = 1
      max_unavailable = 1
    }
EOF
)
fi

cat > "${OUTPUT_DIR}/test-cluster-k8s/terragrunt.hcl" <<EOF
terraform {
  source = "../yc-k8s-module"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "b1g00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id = "enp00000000000000000"
    private_subnets = {
      "${SUBNET_CIDR}" = {
        subnet_id = "e9b00000000000000000"
      }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

dependency "security-group" {
  config_path = "../security-group"
  mock_outputs = {
    id = "enp00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF_PROVIDER
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
EOF_PROVIDER
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cloud_id                                = local.env_vars.locals.cloud_id
  folder_id                               = dependency.folder.outputs.folder_id
  main_folder_id                          = dependency.folder.outputs.folder_id
  yc_zone                                 = local.env_vars.locals.yc_zone
  master_security_group_ids               = [dependency.security-group.outputs.id]
  node_groups_default_security_groups_ids = [dependency.security-group.outputs.id]

  network_id           = dependency.vpc.outputs.vpc_id
  public_access        = ${PUBLIC_ACCESS}
  master_public_ip     = ${MASTER_PUBLIC_ACCESS}
  master_auto_upgrade  = ${MASTER_AUTO_UPGRADE}
  master_version       = "${CLUSTER_VERSION}"
  cluster_version      = "${CLUSTER_VERSION}"
  release_channel      = "${RELEASE_CHANNEL}"
  cni_type             = "${CNI_TYPE}"
  enable_cilium_policy = ${ENABLE_CILIUM_POLICY}
  name                 = "${CLUSTER_NAME}"

  master_locations = [
    {
      zone      = "${YC_ZONE}"
      subnet_id = dependency.vpc.outputs.private_subnets["${SUBNET_CIDR}"].subnet_id
    }
  ]

  master_maintenance_windows = [
    {
      day        = "sunday"
      start_time = "02:00"
      duration   = "2h"
    }
  ]

  cluster_ipv4_range = "172.19.0.0/16"
  service_ipv4_range = "172.20.0.0/16"

  node_groups = {
    "prod-k8s-ng-main" = {
      description = "Main worker nodes group"
      auto_scale = {
        min     = ${WORKER_MIN}
        max     = ${WORKER_MAX}
        initial = ${worker_initial}
      }
      boot_disk_size = ${NODE_BOOT_DISK_GB}
      node_locations = [
        {
          zone      = "${YC_ZONE}"
          subnet_id = dependency.vpc.outputs.private_subnets["${SUBNET_CIDR}"].subnet_id
        }
      ]
      node_labels = {
        role        = "worker"
        environment = "${ENVIRONMENT}"
      }
      max_expansion   = 1
      max_unavailable = 1
    }
${monitoring_group}
  }
}
EOF

cat > "${OUTPUT_DIR}/vault-infra/terragrunt.hcl" <<EOF
terraform {
  source = "../yc-vault-infra-module"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "b1g00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF_PROVIDER
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
EOF_PROVIDER
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cloud_id  = local.env_vars.locals.cloud_id
  folder_id = dependency.folder.outputs.folder_id

  kms_key_name            = "vault-unseal-${CLUSTER_NAME}"
  kms_key_rotation_period = "${KMS_KEY_ROTATION_PERIOD}"
  vault_kms_sa_name       = "vault-kms-sa-${CLUSTER_NAME}"
  create_kms_sa_key       = true

  create_backup_bucket = ${CREATE_BACKUP_BUCKET}
  backup_bucket_name   = ${CREATE_BACKUP_BUCKET} ? "${BACKUP_BUCKET_NAME}" : null
  backup_sa_name       = "vault-backup-sa-${CLUSTER_NAME}"

  labels = {
    component  = "vault"
    managed_by = "terragrunt"
    env        = "${ENVIRONMENT}"
  }
}
EOF

# Patch argocd mock cluster_name to reduce confusion in validate/plan
sed -i.bak -E "s/cluster_name[[:space:]]*=[[:space:]]*\"[^\"]+\"/cluster_name           = \"${CLUSTER_NAME}\"/" "${OUTPUT_DIR}/argocd/terragrunt.hcl" || true
rm -f "${OUTPUT_DIR}/argocd/terragrunt.hcl.bak"

cat > "${OUTPUT_DIR}/.env.example" <<EOF
# Generated for stack: ${STACK_NAME}
# Copy to .env and set real secrets/tokens

TF_VAR_YC_TOKEN=CHANGE_ME_YC_TOKEN
TF_VAR_yc_token=
YC_TOKEN=

K8S_BOX_GITLAB_API_URL=${K8S_BOX_GITLAB_API_URL}
K8S_BOX_GITLAB_GROUP_PATH=${K8S_BOX_GITLAB_GROUP_PATH}
K8S_BOX_GITLAB_SUBGROUP=${K8S_BOX_GITLAB_SUBGROUP}
K8S_BOX_STATIC_GIT_REPO_BASE_URL=${K8S_BOX_STATIC_GIT_REPO_BASE_URL}
K8S_BOX_GITLAB_REPO_USER=${K8S_BOX_GITLAB_REPO_USER}
K8S_BOX_GITLAB_REPO_TOKEN=CHANGE_ME_GITLAB_TOKEN
GITLAB_TOKEN=CHANGE_ME_GITLAB_TOKEN
ARGOCD_ADMIN_PASSWORD=CHANGE_ME_TO_SECURE_PASSWORD

# Observability stack selection for infrastructure repo
K8S_BOX_OBSERVABILITY_STACK=${OBSERVABILITY_STACK}
K8S_BOX_OBSERVABILITY_PROFILE=${OBSERVABILITY_PROFILE}
K8S_BOX_OBSERVABILITY_SECRET_PROVIDER=${OBSERVABILITY_SECRET_PROVIDER}
K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST=${OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST}
K8S_BOX_VAULT_PROFILE=${VAULT_PROFILE}
K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS=${VAULT_ENABLE_BACKUP_MANIFESTS}
K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST=${VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST}

# Generated infrastructure sizing/profile defaults
K8S_BOX_CLUSTER_PROFILE=${ENVIRONMENT}
K8S_BOX_DEPLOYMENT_ENV=${ENVIRONMENT}
K8S_BOX_SUBNET_CIDR=${SUBNET_CIDR}
K8S_BOX_CLUSTER_NAME=${CLUSTER_NAME}
K8S_BOX_CLUSTER_VERSION=${CLUSTER_VERSION}
K8S_BOX_RELEASE_CHANNEL=${RELEASE_CHANNEL}
K8S_BOX_CNI_TYPE=${CNI_TYPE}
K8S_BOX_ENABLE_CILIUM_POLICY=${ENABLE_CILIUM_POLICY}
K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS=${ALLOW_PUBLIC_LOAD_BALANCERS}
K8S_BOX_MASTER_PUBLIC_ACCESS=${MASTER_PUBLIC_ACCESS}
K8S_BOX_MASTER_AUTO_UPGRADE=${MASTER_AUTO_UPGRADE}
K8S_BOX_CLUSTER_IPV4_RANGE=172.19.0.0/16
K8S_BOX_SERVICE_IPV4_RANGE=172.20.0.0/16
K8S_BOX_NODE_CORES=${NODE_VCPU}
K8S_BOX_NODE_MEMORY_GB=${NODE_MEMORY_GIB}
K8S_BOX_NODE_BOOT_DISK_GB=${NODE_BOOT_DISK_GB}
K8S_BOX_WORKER_MIN=${WORKER_MIN}
K8S_BOX_WORKER_MAX=${WORKER_MAX}
K8S_BOX_WORKER_INITIAL=${worker_initial}
K8S_BOX_MONITORING_ENABLED=${ENABLE_MONITORING_NODE}
K8S_BOX_MONITORING_MIN=${MONITORING_MIN}
K8S_BOX_MONITORING_MAX=${MONITORING_MAX}
K8S_BOX_MONITORING_INITIAL=${MONITORING_INITIAL}
K8S_BOX_API_ALLOWED_CIDRS=${API_ALLOWED_CIDRS}
K8S_BOX_SSH_ALLOWED_CIDRS=${SSH_ALLOWED_CIDRS}
K8S_BOX_ENABLE_NLB_HC_RULE=${ENABLE_NLB_HC_RULE}
K8S_BOX_ENABLE_NODEPORT_RULE=${ENABLE_NODEPORT_RULE}
K8S_BOX_NODEPORT_FROM=${NODEPORT_FROM}
K8S_BOX_NODEPORT_TO=${NODEPORT_TO}
K8S_BOX_NODEPORT_ALLOWED_CIDRS=${NODEPORT_ALLOWED_CIDRS}

K8S_BOX_VAULT_KMS_KEY_ROTATION_PERIOD=${KMS_KEY_ROTATION_PERIOD}
K8S_BOX_VAULT_CREATE_BACKUP_BUCKET=${CREATE_BACKUP_BUCKET}
K8S_BOX_VAULT_BACKUP_BUCKET_NAME=${BACKUP_BUCKET_NAME}
EOF

info "Stack scaffold ready: ${OUTPUT_DIR}"
info "Next steps:"
info "  1) cd ${OUTPUT_DIR}"
info "  2) cp .env.example .env && edit .env"
info "  3) ./scripts/check-env.sh"
info "  4) ./scripts/bootstrap-k8s-box.sh apply"
info "  5) ./scripts/apply-platform-runtime-profile.sh"
