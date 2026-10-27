#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${ROOT_DIR}/vpn-vm"
OUTPUT_DIR="${ROOT_DIR}/.artifacts/vpn-clients"
SSH_USER="${K8S_BOX_VPN_VM_SSH_USERNAME:-ubuntu}"
SSH_KEY_PATH="${K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_ed25519}"
SSH_MODE="${K8S_BOX_VPN_VM_SSH_MODE:-native}"

usage() {
  cat <<'EOF'
Использование:
  ./scripts/vpn-create-wireguard-client.sh <client-name> [endpoint-host]

Что делает:
  1. Берет внешний IP VPN VM из terragrunt output.
  2. По SSH вызывает на VPN VM генерацию client-конфига WireGuard.
  3. Сохраняет результат локально в .artifacts/vpn-clients/<client-name>.conf

Требования:
  - стек vpn-vm уже применен;
  - есть operational SSH-доступ до VM:
    - либо обычный SSH (`K8S_BOX_VPN_VM_SSH_MODE=native`);
    - либо `yc compute ssh` с настроенным OS Login (`K8S_BOX_VPN_VM_SSH_MODE=yc`);
  - на VM успешно выполнился cloud-init WireGuard.
EOF
}

get_stack_output() {
  local name="$1"
  (cd "${STACK_DIR}" && terragrunt output -raw "${name}")
}

run_remote_stdout() {
  local host="$1"
  shift

  case "${SSH_MODE}" in
    native)
      ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${host}" "$@"
      ;;
    yc)
      local instance_id=""
      instance_id="$(get_stack_output instance_id)"
      if [[ -z "${instance_id}" || "${instance_id}" == "null" ]]; then
        echo "[ERROR] Не удалось определить instance_id для yc compute ssh" >&2
        exit 1
      fi
      yc compute ssh --id "${instance_id}" --public-address --login "${SSH_USER}" -- "$@"
      ;;
    *)
      echo "[ERROR] Неподдерживаемый K8S_BOX_VPN_VM_SSH_MODE=${SSH_MODE}. Ожидается native или yc." >&2
      exit 1
      ;;
  esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

CLIENT_NAME="$1"
ENDPOINT_HOST="${2:-}"

if [[ -z "${ENDPOINT_HOST}" ]]; then
  ENDPOINT_HOST="$(get_stack_output external_ip)"
fi

if [[ -z "${ENDPOINT_HOST}" || "${ENDPOINT_HOST}" == "null" ]]; then
  echo "[ERROR] Не удалось определить endpoint-host. Передай его вторым аргументом." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/${CLIENT_NAME}.conf"

echo "[INFO] Генерирую WireGuard client config для ${CLIENT_NAME} через ${ENDPOINT_HOST}" >&2
run_remote_stdout "${ENDPOINT_HOST}" \
  "sudo -n /usr/local/bin/vpn-create-client.sh '${CLIENT_NAME}' '${ENDPOINT_HOST}'" \
  > "${OUTPUT_FILE}"

chmod 600 "${OUTPUT_FILE}"
echo "[INFO] Конфиг сохранен: ${OUTPUT_FILE}" >&2
echo "${OUTPUT_FILE}"
