terraform {
  source = "../yc-vault-infra-module"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "b1g00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDER GENERATION
# ---------------------------------------------------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF_PROVIDER
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
EOF_PROVIDER
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  cluster_name        = get_env("K8S_BOX_CLUSTER_NAME", "test-cluster")
  deployment_env      = get_env("K8S_BOX_DEPLOYMENT_ENV", "test")
  kms_rotation_period = get_env("K8S_BOX_VAULT_KMS_KEY_ROTATION_PERIOD", "2160h")

  create_backup_bucket = lower(get_env("K8S_BOX_VAULT_CREATE_BACKUP_BUCKET", "false")) == "true"
  backup_bucket_name   = trimspace(get_env("K8S_BOX_VAULT_BACKUP_BUCKET_NAME", ""))
}

inputs = {
  cloud_id  = local.env_vars.locals.cloud_id
  folder_id = dependency.folder.outputs.folder_id

  # --- KMS for Vault auto-unseal ---
  kms_key_name            = get_env("K8S_BOX_VAULT_KMS_KEY_NAME", "vault-unseal-${local.cluster_name}")
  kms_key_rotation_period = local.kms_rotation_period
  vault_kms_sa_name       = get_env("K8S_BOX_VAULT_KMS_SA_NAME", "vault-kms-sa-${local.cluster_name}")
  create_kms_sa_key       = true

  # --- Object Storage for Raft snapshots ---
  create_backup_bucket = local.create_backup_bucket
  backup_bucket_name   = local.create_backup_bucket ? (local.backup_bucket_name != "" ? local.backup_bucket_name : null) : null
  backup_sa_name       = get_env("K8S_BOX_VAULT_BACKUP_SA_NAME", "vault-backup-sa-${local.cluster_name}")

  labels = {
    component  = "vault"
    managed_by = "terragrunt"
    env        = local.deployment_env
  }
}
