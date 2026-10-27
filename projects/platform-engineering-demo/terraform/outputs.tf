output "grafana_port_forward" {
  description = "Command to open Grafana locally."
  value       = "kubectl -n ${var.observability_namespace} port-forward svc/kube-prometheus-stack-grafana 3000:80"
}

output "prometheus_port_forward" {
  description = "Command to open Prometheus locally."
  value       = "kubectl -n ${var.observability_namespace} port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
}

output "app_namespace" {
  value = var.app_namespace
}

output "observability_namespace" {
  value = var.observability_namespace
}
