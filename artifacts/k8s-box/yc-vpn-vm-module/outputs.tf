output "instance_id" {
  description = "VPN VM instance id"
  value       = yandex_compute_instance.vpn.id
}

output "instance_name" {
  description = "VPN VM instance name"
  value       = yandex_compute_instance.vpn.name
}

output "internal_ip" {
  description = "VPN VM internal IPv4 address"
  value       = try(yandex_compute_instance.vpn.network_interface[0].ip_address, null)
}

output "external_ip" {
  description = "VPN VM external IPv4 address"
  value       = try(yandex_compute_instance.vpn.network_interface[0].nat_ip_address, null)
}

output "service_account_id" {
  description = "Service account id used by VPN VM"
  value       = local.effective_sa_id
}

output "security_group_id" {
  description = "Created VPN security group id (if create_security_group=true)"
  value       = var.create_security_group ? yandex_vpc_security_group.vpn[0].id : null
}
