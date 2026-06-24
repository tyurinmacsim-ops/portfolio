module "argo-project" {
  # source = "gitlab.com/infrastructure/argocd-controller/common"
  # version = "0.5.0"
  source = "../"

  group_path                 = "infrastructure/gitops/yc/test"
  subgroup_name              = "k8s-test"
  subgroup_name_token_prefix = "yc-test"

  import_cluster_subgroup = false

  subgroup_description                 = "ArgoCD Example Cluster"
  argocd_helm_values                   = templatefile("argocd.values.yaml", { "oidc_client_secret" = var.oidc_client_secret })
  gitlab_project_create_example_tenant = false
  projects = {
    monitoring = {
      description                = "Project for monitoring services, such as kube-prometheus-stack, grafana, etc"
      single_namespace           = true
      serverside_apply           = true
      ignore_deployment_replicas = false
    },
    infrastructure = {
      description                = "Project for infra charts ingress-nginx, etc., mostly - infra services"
      single_namespace           = true
      serverside_apply           = true
      ignore_deployment_replicas = false
    },
    vault = {
      description                = "Project for vault charts, e.g. vault,"
      single_namespace           = true
      serverside_apply           = true
      ignore_deployment_replicas = false
    },

    logging = {
      description                = "Project for logging charts, e.g. osh, vecotr,"
      single_namespace           = true
      serverside_apply           = true
      ignore_deployment_replicas = false
    },

  }

  helm_charts_gitlab_repos = {
    infra-helm-charts = "infrastructure/helm-charts/infra-helm-charts"
    apps-helm-charts  = "infrastructure/helm-charts/app-helm-charts"
  }
  # argocd_helm_chart_version = "7.6.12"
  argocd_helm_release_namespace      = local.argocd_namespace
  argocd_admin_password              = var.argocd_admin_password
  argocd_helm_secrets_enabled        = true
  argocd_helm_secrets_create_secrete = true
  gitlab_api_url                     = var.gitlab_api_url
}

output "argocd_admin_password" {
  value     = var.argocd_admin_password
  sensitive = true
}
