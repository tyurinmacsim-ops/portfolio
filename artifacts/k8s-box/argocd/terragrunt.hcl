terraform {
  source = "../argocd-module"

  # Изолируем Helm cache/config от пользовательского ~/.config/helm, чтобы
  # argocd apply не зависел от локально добавленных repo alias и мусорного cache.
  before_hook "prepare_helm_home" {
    commands = ["init", "plan", "apply", "destroy"]
    execute = [
      "bash",
      "-lc",
      "mkdir -p .helm/cache && mkdir -p .helm/config && touch .helm/config/repositories.yaml"
    ]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# Получаем данные о кластере из соседнего модуля (test-cluster-k8s)
# ---------------------------------------------------------------------------------------------------------------------
dependency "k8s" {
  config_path = "../test-cluster-k8s"
  mock_outputs = {
    external_v4_endpoint   = "https://127.0.0.1:6443"
    cluster_ca_certificate = ""
    cluster_id             = "cat00000000000000000"
    cluster_name           = "test-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

locals {
  gitlab_web_url    = get_env("K8S_BOX_GITLAB_WEB_URL", "https://gitlab.example.com")
  gitlab_group_path = get_env("K8S_BOX_GITLAB_GROUP_PATH", "example-group")
  gitlab_subgroup   = get_env("K8S_BOX_GITLAB_SUBGROUP", "infrastructure")
  kube_context      = get_env("K8S_BOX_KUBE_CONTEXT", "yc-${get_env("K8S_BOX_CLUSTER_NAME", "test-cluster")}")
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDER GENERATION
# ---------------------------------------------------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF_PROVIDER
provider "yandex" {
  # Токен берется из env или ~/.config
}

provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "${local.kube_context}"
}

provider "helm" {
  repository_config_path = "${get_terragrunt_dir()}/.helm/config/repositories.yaml"
  repository_cache       = "${get_terragrunt_dir()}/.helm/cache"

  kubernetes {
    config_path    = pathexpand("~/.kube/config")
    config_context = "${local.kube_context}"
  }
}

${get_env("K8S_BOX_ARGOCD_MANAGE_GITLAB", "false") == "true" ? <<EOF_GITLAB
provider "gitlab" {
  base_url = var.gitlab_api_url
}
EOF_GITLAB
: ""}
EOF_PROVIDER
}

# ---------------------------------------------------------------------------------------------------------------------
# INPUTS
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # --- Namespace Settings ---
  # ВАЖНО: Модуль по умолчанию НЕ создает неймспейс. Ставим true.
  argocd_helm_release_create_namespace = true
  argocd_helm_release_namespace        = "argocd"

  # --- GitLab Settings ---
  manage_gitlab  = false
  gitlab_api_url = get_env("K8S_BOX_GITLAB_API_URL", "${local.gitlab_web_url}/api/v4")
  group_path     = local.gitlab_group_path
  # Ожидается структура: <group_path>/<subgroup_name>/infrastructure.git.
  # В test-режиме используем уже существующий репозиторий, без управления GitLab API.
  subgroup_name            = local.gitlab_subgroup
  static_git_repo_base_url = get_env("K8S_BOX_STATIC_GIT_REPO_BASE_URL", "${local.gitlab_web_url}/${local.gitlab_group_path}/${local.gitlab_subgroup}")
  static_git_repo_username = get_env("K8S_BOX_GITLAB_REPO_USER", "gitops-readonly")
  static_git_repo_password = get_env("K8S_BOX_GITLAB_REPO_TOKEN", get_env("GITLAB_TOKEN", ""))

  # --- ArgoCD Access ---
  argocd_admin_password = get_env("ARGOCD_ADMIN_PASSWORD", "CHANGE_ME_TO_SECURE_PASSWORD")
  # --- Projects ---
  projects = {
    "infrastructure" = {
      description                  = "Infrastructure charts"
      single_namespace             = true     # Все чарты попадут в неймспейс 'infrastructure'
      oidc_public_env_group_prefix = "public" # префикс OIDC-групп (любая строка)
      oidc_unique_env_group_prefix = "unique" # второй префикс
    }
  }
}
