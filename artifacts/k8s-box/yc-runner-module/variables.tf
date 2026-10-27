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
  description = "Folder ID where infra-runner is created"
  type        = string
}

variable "yc_zone" {
  description = "Zone for infra-runner VM"
  type        = string
}

variable "name" {
  description = "Runner VM name"
  type        = string
  default     = "infra-runner"
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

variable "subnet_id" {
  description = "Subnet ID for runner NIC"
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to runner NIC"
  type        = list(string)
  default     = []
}

variable "nat" {
  description = "Enable external NAT for runner"
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
  default     = true
}

variable "user_data" {
  description = "cloud-init user-data rendered from template"
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels for runner VM"
  type        = map(string)
  default     = {}
}

variable "create_service_account" {
  description = "Create dedicated service account for runner VM"
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
  default     = "infra-runner-sa"
}

variable "service_account_roles" {
  description = "Folder IAM roles for created runner service account"
  type        = list(string)
  default     = ["editor"]
}
