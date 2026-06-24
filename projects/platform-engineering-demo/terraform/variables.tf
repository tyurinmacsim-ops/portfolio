variable "kubeconfig_path" {
  description = "Path to kubeconfig used by Terraform providers."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context to target."
  type        = string
  default     = "kind-platform-demo"
}

variable "app_namespace" {
  description = "Namespace for application workloads."
  type        = string
  default     = "apps"
}

variable "observability_namespace" {
  description = "Namespace for Prometheus, Grafana, and Loki."
  type        = string
  default     = "observability"
}

variable "grafana_admin_password" {
  description = "Grafana admin password for the demo environment."
  type        = string
  default     = "admin123"
  sensitive   = true
}
