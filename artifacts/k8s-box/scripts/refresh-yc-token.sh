#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Использование:
  source <(./scripts/refresh-yc-token.sh)
  ./scripts/refresh-yc-token.sh --plain

По умолчанию печатает export-команды для безопасной загрузки свежего YC IAM токена
сразу в TF_VAR_YC_TOKEN, TF_VAR_yc_token и YC_TOKEN.

Это защищает от shell-ловушки, когда в одной строке со смешанными export
используется старое значение TF_VAR_YC_TOKEN из текущего окружения.
EOF
}

mode="exports"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--plain" ]]; then
  mode="plain"
fi

command -v yc >/dev/null 2>&1 || {
  echo "[ERROR] yc не найден в PATH" >&2
  exit 1
}

token="$(yc iam create-token)"
if [[ -z "${token}" ]]; then
  echo "[ERROR] yc iam create-token вернул пустой токен" >&2
  exit 1
fi

if [[ "${mode}" == "plain" ]]; then
  printf '%s\n' "${token}"
  exit 0
fi

printf "export TF_VAR_YC_TOKEN=%q\n" "${token}"
printf "export TF_VAR_yc_token=%q\n" "${token}"
printf "export YC_TOKEN=%q\n" "${token}"
