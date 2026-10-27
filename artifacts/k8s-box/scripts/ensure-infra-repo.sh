#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOCAL_DEFAULT_INFRA_REPO_DIR="${ROOT_DIR}/../infrastructure"
CI_DEFAULT_INFRA_REPO_DIR="${ROOT_DIR}/.deps/infrastructure"
INFRA_REPO_DIR="${INFRA_REPO_DIR:-}"
K8S_BOX_INFRA_REPO_REF="${K8S_BOX_INFRA_REPO_REF:-main}"
UPDATE_INFRA_REPO="${UPDATE_INFRA_REPO:-true}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

is_placeholder() {
  local value="${1:-}"
  [[ -z "${value}" ]] && return 0
  [[ "${value}" == *"CHANGE_ME"* ]] && return 0
  [[ "${value}" == "<"*">" ]] && return 0
  [[ "${value}" == "string" ]] && return 0
  return 1
}

pick_repo_dir() {
  if [[ -n "${INFRA_REPO_DIR}" ]]; then
    printf '%s' "${INFRA_REPO_DIR}"
    return 0
  fi

  if [[ -d "${LOCAL_DEFAULT_INFRA_REPO_DIR}/.git" ]]; then
    printf '%s' "${LOCAL_DEFAULT_INFRA_REPO_DIR}"
    return 0
  fi

  printf '%s' "${CI_DEFAULT_INFRA_REPO_DIR}"
}

build_clone_url() {
  if ! is_placeholder "${K8S_BOX_INFRA_REPO_CLONE_URL:-}"; then
    printf '%s' "${K8S_BOX_INFRA_REPO_CLONE_URL}"
    return 0
  fi

  local base_url="${K8S_BOX_STATIC_GIT_REPO_BASE_URL:-}"
  is_placeholder "${base_url}" && fail "Задай K8S_BOX_INFRA_REPO_CLONE_URL или K8S_BOX_STATIC_GIT_REPO_BASE_URL"
  base_url="${base_url%/}"

  if [[ "${base_url}" == *.git ]]; then
    printf '%s' "${base_url}"
    return 0
  fi

  printf '%s/infrastructure.git' "${base_url}"
}

auth_header() {
  local user="${K8S_BOX_GITLAB_REPO_USER:-}"
  local token="${K8S_BOX_GITLAB_REPO_TOKEN:-${GITLAB_TOKEN:-}}"

  is_placeholder "${user}" && fail "Для clone infrastructure repo задай K8S_BOX_GITLAB_REPO_USER"
  is_placeholder "${token}" && fail "Для clone infrastructure repo задай K8S_BOX_GITLAB_REPO_TOKEN или GITLAB_TOKEN"

  printf 'AUTHORIZATION: Basic %s' "$(printf '%s:%s' "${user}" "${token}" | base64 | tr -d '\n')"
}

clone_repo() {
  local repo_dir="$1"
  local clone_url="$2"
  local header="$3"

  mkdir -p "$(dirname "${repo_dir}")"
  info "Клонируем infrastructure repo в ${repo_dir}"
  git -c http.extraheader="${header}" clone "${clone_url}" "${repo_dir}" >/dev/null
}

update_repo() {
  local repo_dir="$1"
  local header="$2"

  info "Обновляем infrastructure repo в ${repo_dir}"
  git -C "${repo_dir}" -c http.extraheader="${header}" fetch --all --prune >/dev/null

  if git -C "${repo_dir}" show-ref --verify --quiet "refs/remotes/origin/${K8S_BOX_INFRA_REPO_REF}"; then
    git -C "${repo_dir}" checkout -B "${K8S_BOX_INFRA_REPO_REF}" "origin/${K8S_BOX_INFRA_REPO_REF}" >/dev/null 2>&1
  else
    git -C "${repo_dir}" checkout "${K8S_BOX_INFRA_REPO_REF}" >/dev/null 2>&1
  fi
}

main() {
  local repo_dir clone_url header

  repo_dir="$(pick_repo_dir)"
  clone_url="$(build_clone_url)"
  header="$(auth_header)"

  export INFRA_REPO_DIR="${repo_dir}"

  if [[ -d "${repo_dir}/.git" ]]; then
    if [[ "${UPDATE_INFRA_REPO}" == "true" ]]; then
      update_repo "${repo_dir}" "${header}"
    else
      info "Используем существующий infrastructure repo: ${repo_dir}"
    fi
  else
    clone_repo "${repo_dir}" "${clone_url}" "${header}"
    update_repo "${repo_dir}" "${header}"
  fi

  [[ -x "${repo_dir}/.ci/validate-gitops.sh" ]] || warn "В ${repo_dir} не найден исполняемый .ci/validate-gitops.sh"
  info "INFRA_REPO_DIR=${repo_dir}"
}

main "$@"
