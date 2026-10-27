terraform {
  source = "../yc-vpc-module"
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

  network_name  = get_env("K8S_BOX_NETWORK_NAME", local.env_vars.locals.network_name)
  subnet_cidr   = get_env("K8S_BOX_SUBNET_CIDR", "10.0.1.0/24")
  subnet_zone   = get_env("K8S_BOX_SUBNET_ZONE", local.env_vars.locals.yc_zone)
  create_nat_gw = lower(get_env("K8S_BOX_CREATE_NAT_GW", "true")) == "true"
}

inputs = {
  folder_id    = dependency.folder.outputs.folder_id
  network_name = local.network_name
  cloud_id     = local.env_vars.locals.cloud_id

  private_subnets = [
    {
      v4_cidr_blocks = [local.subnet_cidr]
      zone           = local.subnet_zone
    }
  ]

  create_nat_gw = local.create_nat_gw
}
