#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${ROOT_DIR}/vpn-vm"
SSH_USER="${K8S_BOX_VPN_VM_SSH_USERNAME:-ubuntu}"
SSH_KEY_PATH="${K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_ed25519}"
SSH_MODE="${K8S_BOX_VPN_VM_SSH_MODE:-native}"

usage() {
  cat <<'EOF'
Использование:
  ./scripts/vpn-smoke-check.sh [host]

Проверяет:
  - доступ по SSH до VPN VM;
  - статус wg-quick@wg0;
  - вывод wg show;
  - наличие адреса на интерфейсе wg0.
EOF
}

get_stack_output() {
  local name="$1"
  (cd "${STACK_DIR}" && terragrunt output -raw "${name}")
}

run_remote() {
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

HOST="${1:-}"
if [[ -z "${HOST}" ]]; then
  HOST="$(get_stack_output external_ip)"
fi

if [[ -z "${HOST}" || "${HOST}" == "null" ]]; then
  echo "[ERROR] Не удалось определить внешний IP VPN VM" >&2
  exit 1
fi

echo "[INFO] Проверяю WireGuard VPN VM ${HOST}" >&2
run_remote "${HOST}" "sudo -n /usr/local/bin/vpn-wireguard-status.sh"
