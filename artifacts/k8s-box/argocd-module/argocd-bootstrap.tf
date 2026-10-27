locals {
  default_argocd_helm_values    = ""
  helm_secrets_configure_values = var.argocd_helm_secrets_enabled ? file("${path.module}/helm-values/sops-values.yaml") : ""
  static_repo_base_url          = trimsuffix(var.static_git_repo_base_url, "/")
  git_repo_urls = {
    for repo_name, _ in var.projects : repo_name => "${local.static_repo_base_url}/${repo_name}.git"
  }
  git_repo_username = var.static_git_repo_username
  git_repo_passwords = {
    for repo_name, _ in var.projects : repo_name => var.static_git_repo_password
  }
  chart_repo_urls      = {}
  chart_repo_passwords = {}

  repositories_values = templatefile("${path.module}/helm-values/repositories.yaml.tftpl", {
    git_repo_urls        = local.git_repo_urls,
    git_repo_username    = local.git_repo_username,
    git_repo_passwords   = local.git_repo_passwords,
    chart_repo_urls      = local.chart_repo_urls,
    chart_repo_username  = local.git_repo_username,
    chart_repo_passwords = local.chart_repo_passwords
  })
}

resource "bcrypt_hash" "argocd_admin_password_hash" {
  count     = var.argocd_set_admin_user_password ? 1 : 0
  cleartext = var.argocd_admin_password
}


resource "helm_release" "argocd" {
  name             = var.argocd_helm_release_name
  namespace        = var.argocd_helm_release_namespace
  create_namespace = var.argocd_helm_release_create_namespace
  repository       = var.argocd_helm_chart_repo
  chart            = var.argocd_helm_chart_name
  version          = var.argocd_helm_chart_version
  values           = [local.default_argocd_helm_values, local.helm_secrets_configure_values, local.repositories_values, var.argocd_helm_values]

  depends_on = [
    bcrypt_hash.argocd_admin_password_hash,
    kubernetes_secret_v1.sops_secret_keys,
  ]

  dynamic "set" {
    # for_each = var.argocd_set_admin_user_password ? toset([data.external.argocd_admin_password_hash.result["hashed_password"]]) : toset([])
    for_each = var.argocd_set_admin_user_password ? toset([resource.bcrypt_hash.argocd_admin_password_hash[0].id]) : toset([])
    content {
      name  = "configs.secret.argocdServerAdminPassword"
      value = set.value
    }
  }

}

resource "age_secret_key" "helm_secrets_age_key" {
  count = var.argocd_helm_secrets_create_secrete ? 1 : 0
}

resource "kubernetes_secret_v1" "argocd_admin_credentials" {
  count = var.argocd_set_admin_user_password && var.argocd_create_admin_credentials_secret ? 1 : 0

  metadata {
    name      = "argocd-admin-credentials"
    namespace = var.argocd_helm_release_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    annotations = {
      "k8s-box.hilbertteam.com/note" = "Contains plain admin credentials for operational bootstrap access"
    }
  }

  data = {
    username = var.argocd_admin_user
    password = var.argocd_admin_password
  }
  type = "Opaque"

  depends_on = [
    helm_release.argocd,
  ]
}

resource "kubernetes_secret_v1" "sops_secret_keys" {
  count = var.argocd_helm_secrets_create_secrete ? 1 : 0
  metadata {
    name      = "helm-secrets-private-keys"
    namespace = var.argocd_helm_release_namespace
  }

  data = {
    "key.txt" = <<EOF
# public key: ${age_secret_key.helm_secrets_age_key[0].public_key}
${age_secret_key.helm_secrets_age_key[0].secret_key}
EOF
  }
  type = "Opaque"
}
