terraform {
  source = "../yc-runner-module"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "b1g00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    private_subnets = {
      "10.0.1.0/24" = {
        subnet_id = "e9b00000000000000000"
      }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

dependency "security-group" {
  config_path = "../security-group"
  mock_outputs = {
    id = "enp00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.yc_zone
}
EOF
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  deployment_env                = get_env("K8S_BOX_DEPLOYMENT_ENV", "test")
  runner_subnet_cidr            = get_env("K8S_BOX_INFRA_RUNNER_SUBNET_CIDR", get_env("K8S_BOX_SUBNET_CIDR", "10.0.1.0/24"))
  runner_name                   = get_env("K8S_BOX_INFRA_RUNNER_NAME", "infra-runner")
  runner_tags                   = get_env("K8S_BOX_INFRA_RUNNER_TAGS", "infra-runner")
  runner_registration_token     = get_env("K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN", "CHANGE_ME_RUNNER_REGISTRATION_TOKEN")
  runner_gitlab_url             = get_env("K8S_BOX_GITLAB_URL", "https://gitlab.example.com")
  runner_terraform_version      = get_env("K8S_BOX_RUNNER_TERRAFORM_VERSION", "1.12.2")
  runner_terragrunt_version     = get_env("K8S_BOX_RUNNER_TERRAGRUNT_VERSION", "0.82.0")
  runner_platform_id            = get_env("K8S_BOX_INFRA_RUNNER_PLATFORM_ID", "standard-v3")
  runner_cores                  = tonumber(get_env("K8S_BOX_INFRA_RUNNER_CORES", "2"))
  runner_memory_gb              = tonumber(get_env("K8S_BOX_INFRA_RUNNER_MEMORY_GB", "2"))
  runner_core_fraction          = tonumber(get_env("K8S_BOX_INFRA_RUNNER_CORE_FRACTION", "50"))
  runner_boot_disk_size_gb      = tonumber(get_env("K8S_BOX_INFRA_RUNNER_BOOT_DISK_GB", "30"))
  runner_boot_image_family      = get_env("K8S_BOX_INFRA_RUNNER_IMAGE_FAMILY", "ubuntu-2204-lts")
  runner_create_service_account = lower(get_env("K8S_BOX_INFRA_RUNNER_CREATE_SERVICE_ACCOUNT", "true")) == "true"
  runner_service_account_name   = get_env("K8S_BOX_INFRA_RUNNER_SERVICE_ACCOUNT_NAME", "infra-runner-sa")
}

inputs = {
  cloud_id  = local.env_vars.locals.cloud_id
  folder_id = dependency.folder.outputs.folder_id
  yc_zone   = local.env_vars.locals.yc_zone

  name              = local.runner_name
  platform_id       = local.runner_platform_id
  cores             = local.runner_cores
  memory            = local.runner_memory_gb
  core_fraction     = local.runner_core_fraction
  boot_disk_size    = local.runner_boot_disk_size_gb
  boot_image_family = local.runner_boot_image_family

  subnet_id          = try(dependency.vpc.outputs.private_subnets[local.runner_subnet_cidr].subnet_id, values(dependency.vpc.outputs.private_subnets)[0].subnet_id)
  security_group_ids = [dependency.security-group.outputs.id]
  nat                = true

  create_service_account = local.runner_create_service_account
  service_account_name   = local.runner_service_account_name
  service_account_roles  = ["editor"]

  user_data = templatefile("${get_terragrunt_dir()}/../runner/cloud-init-gitlab-runner.yaml.tpl", {
    gitlab_url                = local.runner_gitlab_url
    runner_registration_token = local.runner_registration_token
    runner_name               = local.runner_name
    runner_tags               = local.runner_tags
    terraform_version         = local.runner_terraform_version
    terragrunt_version        = local.runner_terragrunt_version
  })

  labels = {
    environment = local.deployment_env
    managed_by  = "terraform"
    role        = "infra-runner"
  }
}
