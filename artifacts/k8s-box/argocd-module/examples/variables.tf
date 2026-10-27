variable "argocd_admin_password" {
  type        = string
  sensitive   = true
  description = "Admin password for argocd"
}

variable "gitlab_api_url" {
  type    = string
  default = "https://gitlab.com/api/v4"
}

variable "oidc_client_secret" {
  type      = string
  default   = ""
  sensitive = false
}
