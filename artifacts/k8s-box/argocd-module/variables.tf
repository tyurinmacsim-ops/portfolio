variable "gitlab_api_url" {
  type    = string
  default = "https://gitlab.com/api/v4/"
}

variable "manage_gitlab" {
  type        = bool
  default     = true
  description = "When true, module manages GitLab subgroup/projects/tokens. Set false to use pre-created repositories and static credentials."
}

variable "static_git_repo_base_url" {
  type        = string
  default     = ""
  description = "Base URL for pre-created Git repositories when manage_gitlab=false. Example: https://gitlab.example.com/group/subgroup"
}

variable "static_git_repo_username" {
  type        = string
  default     = ""
  description = "Username for accessing static repositories when manage_gitlab=false."
}

variable "static_git_repo_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Password/token for accessing static repositories when manage_gitlab=false."
}
# Groups
variable "group_path" {
  type = string
}

variable "subgroup_name" {
  type        = string
  description = "Subgroup for projects will be created"
}

variable "subgroup_name_token_prefix" {
  type        = string
  description = "Prefix for use in gitlab tokens in helm repos to indetify which scope token belongs to"
  default     = ""
}

variable "import_cluster_subgroup" {
  type    = bool
  default = false
}

variable "subgroup_description" {
  type        = string
  description = "Description for subgroup"
  default     = ""
}

# Projects
variable "projects" {
  type = map(object(
    {
      environments                 = optional(list(string), [""])
      description                  = string
      single_namespace             = optional(bool, true)
      serverside_apply             = optional(bool, false)
      ignore_deployment_replicas   = optional(bool, false)
      oidc_public_env_group_prefix = string
      oidc_unique_env_group_prefix = string
    }
  ))
  description = "Projects for gitops-controller with environments if present, please use '' for no env"
}

variable "token_expiration_days" {
  type        = number
  description = "Set days, when argocd token wil be expired"
  default     = 365
}

variable "token_rotate_before_days" {
  type        = number
  description = "Set days, when argocd token wil be rotated"
  default     = 30
}

variable "helm_charts_gitlab_repos" {
  type        = map(string)
  description = "Path to repository with charts"
  default     = {}
}


variable "gitlab_user_project_access_level" {
  type        = string
  default     = "maintainer"
  description = "gitlab user project access level (owner|maintainer|developer|reporter)"
}

variable "gitlab_project_create_example_tenant" {
  type        = bool
  default     = true
  description = "Create exapmple tenant"
}


##### ArgoCD Helm ######
variable "argocd_helm_release_name" {
  type    = string
  default = "argocd"
}

variable "argocd_helm_release_namespace" {
  type    = string
  default = "argocd"
}

variable "argocd_helm_release_create_namespace" {
  type    = bool
  default = false
}


variable "argocd_helm_chart_repo" {
  type    = string
  default = "https://argoproj.github.io/argo-helm"
}


variable "argocd_helm_chart_name" {
  type    = string
  default = "argo-cd"
}


variable "argocd_helm_chart_version" {
  type    = string
  default = "7.7.16"
}

variable "argocd_helm_values" {
  type    = string
  default = ""
}

##### ArgoCD Apps Helm ######
variable "argocd_apps_helm_release_name" {
  type    = string
  default = "argocd-apps"
}

variable "argocd_apps_helm_release_namespace" {
  type    = string
  default = "argocd"
}

variable "argocd_apps_helm_release_create_namespace" {
  type    = bool
  default = false
}


variable "argocd_apps_helm_chart_repo" {
  type    = string
  default = "https://argoproj.github.io/argo-helm"
}


variable "argocd_apps_helm_chart_name" {
  type    = string
  default = "argocd-apps"
}


variable "argocd_apps_helm_chart_version" {
  type    = string
  default = "2.0.2"
}

variable "argocd_apps_helm_values" {
  type    = string
  default = ""
}

##### ArgoCD Configure ######

variable "argocd_admin_user" {
  type    = string
  default = "admin"
}

variable "argocd_admin_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "argocd_set_admin_user_password" {
  description = "Generate sha and set  password for admin. Sha generated for user 'admin'"
  type        = bool
  default     = true
}

variable "argocd_create_admin_credentials_secret" {
  description = "Create additional plain-text secret argocd-admin-credentials with admin username/password for operational access"
  type        = bool
  default     = true
}

variable "argocd_helm_secrets_enabled" {
  description = "Enable helm secrets to have ability to encrypt secrets.yaml"
  type        = bool
  default     = false
}

variable "argocd_helm_secrets_create_secrete" {
  description = "Create age secret for  helm secrets plugin"
  type        = bool
  default     = false
}
