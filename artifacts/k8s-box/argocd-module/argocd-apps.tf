locals {
  default_argocd_apps_helm_values = ""
  argocd_apps_projects_helm_values = templatefile("${path.module}/helm-values/projects.yaml.tftpl", {
    projects  = var.projects,
    namespace = var.argocd_helm_release_namespace
  })
  argocd_apps_appsets_helm_values = templatefile("${path.module}/helm-values/applicationsets.yaml.tftpl", {
    projects                    = var.projects,
    namespace                   = var.argocd_helm_release_namespace,
    git_repo_urls               = local.git_repo_urls,
    argocd_helm_secrets_enabled = var.argocd_helm_secrets_enabled
  })
}

resource "helm_release" "argocd_apps" {
  name             = var.argocd_apps_helm_release_name
  namespace        = var.argocd_apps_helm_release_namespace
  create_namespace = var.argocd_apps_helm_release_create_namespace
  repository       = var.argocd_apps_helm_chart_repo
  chart            = var.argocd_apps_helm_chart_name
  version          = var.argocd_apps_helm_chart_version
  values           = [local.argocd_apps_projects_helm_values, local.argocd_apps_appsets_helm_values, var.argocd_apps_helm_values]

  depends_on = [
    helm_release.argocd
  ]

}
