terraform {
  source = "../yc-folder-module"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDER GENERATION
# ---------------------------------------------------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "yandex" {
  token    = var.yc_token
  cloud_id = var.cloud_id
}
EOF
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  folders = {
    "k8s-box" = {
      cloud_id           = local.env_vars.locals.cloud_id
      folder_name        = local.env_vars.locals.folder_name
      folder_description = "Folder for k8s-box"
    }
  }
  # Передаем переменные для провайдера
  cloud_id = local.env_vars.locals.cloud_id
}
