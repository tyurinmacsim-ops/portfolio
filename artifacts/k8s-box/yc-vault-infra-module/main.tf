resource "yandex_kms_symmetric_key" "vault_unseal" {
  folder_id = var.folder_id

  name                = var.kms_key_name
  description         = var.kms_key_description
  default_algorithm   = var.kms_key_default_algorithm
  rotation_period     = var.kms_key_rotation_period
  deletion_protection = var.kms_key_deletion_protection
  labels              = var.labels
}

resource "yandex_iam_service_account" "vault_kms_sa" {
  folder_id   = var.folder_id
  name        = var.vault_kms_sa_name
  description = var.vault_kms_sa_description
  labels      = var.labels
}

resource "yandex_kms_symmetric_key_iam_member" "vault_unseal_binding" {
  symmetric_key_id = yandex_kms_symmetric_key.vault_unseal.id
  role             = "kms.keys.encrypterDecrypter"
  member           = "serviceAccount:${yandex_iam_service_account.vault_kms_sa.id}"
}

resource "yandex_iam_service_account_key" "vault_kms_sa_key" {
  count = var.create_kms_sa_key ? 1 : 0

  service_account_id = yandex_iam_service_account.vault_kms_sa.id
  description        = "Authorized key for Vault KMS auto-unseal"
  key_algorithm      = var.kms_sa_key_algorithm
}

resource "yandex_iam_service_account" "vault_backup_sa" {
  count = var.create_backup_bucket ? 1 : 0

  folder_id   = var.folder_id
  name        = var.backup_sa_name
  description = var.backup_sa_description
  labels      = var.labels
}

resource "yandex_resourcemanager_folder_iam_member" "vault_backup_sa_storage_admin" {
  count = var.create_backup_bucket ? 1 : 0

  folder_id = var.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.vault_backup_sa[0].id}"
}

resource "yandex_iam_service_account_static_access_key" "vault_backup_sa_key" {
  count = var.create_backup_bucket ? 1 : 0

  service_account_id = yandex_iam_service_account.vault_backup_sa[0].id
  description        = "Static key for Vault raft snapshot uploads"

  depends_on = [
    yandex_resourcemanager_folder_iam_member.vault_backup_sa_storage_admin,
  ]
}

resource "yandex_storage_bucket" "vault_backups" {
  count = var.create_backup_bucket ? 1 : 0

  bucket        = var.backup_bucket_name
  access_key    = yandex_iam_service_account_static_access_key.vault_backup_sa_key[0].access_key
  secret_key    = yandex_iam_service_account_static_access_key.vault_backup_sa_key[0].secret_key
  force_destroy = var.backup_bucket_force_destroy
  max_size      = var.backup_bucket_max_size

  anonymous_access_flags {
    read        = false
    list        = false
    config_read = false
  }

  versioning {
    enabled = var.backup_bucket_versioning_enabled
  }

  lifecycle {
    precondition {
      condition     = var.backup_bucket_name != null && length(var.backup_bucket_name) >= 3
      error_message = "Set backup_bucket_name when create_backup_bucket = true."
    }
  }
}
