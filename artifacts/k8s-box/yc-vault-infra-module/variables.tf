variable "cloud_id" {
  description = "Cloud ID used by provider generation in Terragrunt"
  type        = string
}

variable "yc_token" {
  description = "OAuth token for Yandex Cloud"
  type        = string
  default     = null
  sensitive   = true
}

variable "folder_id" {
  description = "Folder ID where Vault infra resources are created"
  type        = string
}

variable "labels" {
  description = "Common labels for resources that support labels"
  type        = map(string)
  default     = {}
}

variable "kms_key_name" {
  description = "KMS key name for Vault auto-unseal"
  type        = string
  default     = "vault-unseal-key"
}

variable "kms_key_description" {
  description = "KMS key description for Vault auto-unseal"
  type        = string
  default     = "KMS key for HashiCorp Vault auto-unseal"
}

variable "kms_key_rotation_period" {
  description = "KMS key rotation period, for example 2160h or 8760h"
  type        = string
  default     = "2160h"
}

variable "kms_key_default_algorithm" {
  description = "KMS key algorithm"
  type        = string
  default     = "AES_256"
}

variable "kms_key_deletion_protection" {
  description = "Protect KMS key from accidental deletion"
  type        = bool
  default     = true
}

variable "vault_kms_sa_name" {
  description = "Service account name used by Vault for KMS auto-unseal"
  type        = string
  default     = "vault-kms-sa"
}

variable "vault_kms_sa_description" {
  description = "Description for Vault KMS service account"
  type        = string
  default     = "Service account for Vault KMS auto-unseal"
}

variable "create_kms_sa_key" {
  description = "Create static JSON authorized key for Vault KMS service account"
  type        = bool
  default     = true
}

variable "kms_sa_key_algorithm" {
  description = "Authorized key algorithm for Vault KMS service account"
  type        = string
  default     = "RSA_4096"
}

variable "create_backup_bucket" {
  description = "Create Object Storage bucket and service account for Raft snapshots"
  type        = bool
  default     = false
}

variable "backup_bucket_name" {
  description = "Globally unique Object Storage bucket name for Vault backups"
  type        = string
  default     = null

  validation {
    condition     = var.backup_bucket_name == null ? true : length(var.backup_bucket_name) >= 3
    error_message = "backup_bucket_name must be null or at least 3 chars long."
  }
}

variable "backup_bucket_force_destroy" {
  description = "Allow bucket deletion with objects inside (recommended false for prod)"
  type        = bool
  default     = false
}

variable "backup_bucket_max_size" {
  description = "Bucket max size in bytes; null means unlimited"
  type        = number
  default     = null
}

variable "backup_bucket_versioning_enabled" {
  description = "Enable bucket versioning for backup safety"
  type        = bool
  default     = true
}

variable "backup_sa_name" {
  description = "Service account name used for writing Vault backups"
  type        = string
  default     = "vault-backup-sa"
}

variable "backup_sa_description" {
  description = "Description for Vault backup service account"
  type        = string
  default     = "Service account for Vault raft snapshot backups"
}
