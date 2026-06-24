variable "yc_token" {
  description = "Yandex Cloud IAM token"
  type        = string
  sensitive   = true
}

variable "cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
}

variable "folder_id" {
  description = "Folder ID where VPN VM is created"
  type        = string
}

variable "yc_zone" {
  description = "Zone for VPN VM"
  type        = string
}

variable "network_id" {
  description = "VPC network ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for VPN VM NIC"
  type        = string
}

variable "name" {
  description = "VPN VM name"
  type        = string
  default     = "vpn-vm"
}

variable "platform_id" {
  description = "Compute platform"
  type        = string
  default     = "standard-v3"
}

variable "cores" {
  description = "vCPU count"
  type        = number
  default     = 2
}

variable "memory" {
  description = "RAM in GB"
  type        = number
  default     = 2
}

variable "core_fraction" {
  description = "Guaranteed vCPU fraction"
  type        = number
  default     = 50
}

variable "boot_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 30
}

variable "boot_disk_type" {
  description = "Boot disk type"
  type        = string
  default     = "network-ssd"
}

variable "boot_image_family" {
  description = "Yandex image family for VM boot disk"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "nat" {
  description = "Enable external NAT for VPN VM"
  type        = bool
  default     = true
}

variable "allow_stopping_for_update" {
  description = "Allow stop/start during updates"
  type        = bool
  default     = true
}

variable "enable_oslogin" {
  description = "Enable Yandex OS Login"
  type        = bool
  default     = false
}

variable "user_data" {
  description = "cloud-init user-data rendered from template"
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels for VPN VM"
  type        = map(string)
  default     = {}
}

variable "ssh_username" {
  description = "Linux username for injected SSH public key"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key content injected into instance metadata when OS Login is disabled"
  type        = string
  default     = ""
}

variable "create_service_account" {
  description = "Create dedicated service account for VPN VM"
  type        = bool
  default     = true
}

variable "service_account_id" {
  description = "Existing service account id. If set, module will not create SA"
  type        = string
  default     = ""
}

variable "service_account_name" {
  description = "Service account name if create_service_account=true"
  type        = string
  default     = "vpn-vm-sa"
}

variable "service_account_roles" {
  description = "Folder IAM roles for created VPN service account"
  type        = list(string)
  default     = ["editor"]
}

variable "create_security_group" {
  description = "Create dedicated security group for VPN VM"
  type        = bool
  default     = true
}

variable "admin_cidr_blocks" {
  description = "CIDRs allowed for SSH access to VPN VM"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_openvpn" {
  description = "Open UDP OpenVPN port in SG"
  type        = bool
  default     = true
}

variable "openvpn_port" {
  description = "OpenVPN UDP port"
  type        = number
  default     = 1194
}

variable "enable_wireguard" {
  description = "Open UDP WireGuard port in SG"
  type        = bool
  default     = true
}

variable "wireguard_port" {
  description = "WireGuard UDP port"
  type        = number
  default     = 51820
}

variable "additional_security_group_ids" {
  description = "Additional security groups attached to VPN VM NIC"
  type        = list(string)
  default     = []
}
