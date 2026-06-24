output "instance_id" {
  description = "Infra runner instance id"
  value       = yandex_compute_instance.runner.id
}

output "instance_name" {
  description = "Infra runner instance name"
  value       = yandex_compute_instance.runner.name
}

output "internal_ip" {
  description = "Infra runner internal IPv4 address"
  value       = try(yandex_compute_instance.runner.network_interface[0].ip_address, null)
}

output "external_ip" {
  description = "Infra runner external IPv4 address"
  value       = try(yandex_compute_instance.runner.network_interface[0].nat_ip_address, null)
}

output "service_account_id" {
  description = "Service account id used by infra runner"
  value       = local.effective_sa_id
}
