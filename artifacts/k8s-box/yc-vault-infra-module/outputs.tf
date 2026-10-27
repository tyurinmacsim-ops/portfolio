output "vault_unseal_kms_key_id" {
  description = "KMS key ID used by Vault auto-unseal"
  value       = yandex_kms_symmetric_key.vault_unseal.id
}

output "vault_unseal_kms_key_name" {
  description = "KMS key name used by Vault auto-unseal"
  value       = yandex_kms_symmetric_key.vault_unseal.name
}

output "vault_kms_service_account_id" {
  description = "Service account ID used by Vault for KMS auto-unseal"
  value       = yandex_iam_service_account.vault_kms_sa.id
}

output "vault_kms_service_account_name" {
  description = "Service account name used by Vault for KMS auto-unseal"
  value       = yandex_iam_service_account.vault_kms_sa.name
}

output "vault_kms_service_account_key_json" {
  description = "Authorized key JSON for Vault auto-unseal integration (store securely)"
  value = var.create_kms_sa_key ? jsonencode({
    id                 = yandex_iam_service_account_key.vault_kms_sa_key[0].id
    service_account_id = yandex_iam_service_account_key.vault_kms_sa_key[0].service_account_id
    created_at         = yandex_iam_service_account_key.vault_kms_sa_key[0].created_at
    key_algorithm      = yandex_iam_service_account_key.vault_kms_sa_key[0].key_algorithm
    public_key         = yandex_iam_service_account_key.vault_kms_sa_key[0].public_key
    private_key        = yandex_iam_service_account_key.vault_kms_sa_key[0].private_key
  }) : null
  sensitive = true
}

output "vault_backup_bucket_name" {
  description = "Object Storage bucket name for Vault backups"
  value       = try(yandex_storage_bucket.vault_backups[0].bucket, null)
}

output "vault_backup_bucket_domain_name" {
  description = "Object Storage bucket domain name for backup uploads"
  value       = try(yandex_storage_bucket.vault_backups[0].bucket_domain_name, null)
}

output "vault_backup_service_account_id" {
  description = "Service account ID used for Vault backup uploads"
  value       = try(yandex_iam_service_account.vault_backup_sa[0].id, null)
}

output "vault_backup_access_key" {
  description = "Static access key for backup uploader"
  value       = try(yandex_iam_service_account_static_access_key.vault_backup_sa_key[0].access_key, null)
  sensitive   = true
}

output "vault_backup_secret_key" {
  description = "Static secret key for backup uploader"
  value       = try(yandex_iam_service_account_static_access_key.vault_backup_sa_key[0].secret_key, null)
  sensitive   = true
}
