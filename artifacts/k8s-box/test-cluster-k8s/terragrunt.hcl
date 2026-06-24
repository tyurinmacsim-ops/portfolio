terraform {
  source = "../yc-k8s-module"
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
    vpc_id = "enp00000000000000000"
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
  contents  = <<EOF_PROVIDER
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
EOF_PROVIDER
}

locals {
  env_vars      = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  profiles_conf = read_terragrunt_config("${get_terragrunt_dir()}/../profiles/cluster-profiles.hcl")

  cluster_profile_name = get_env("K8S_BOX_CLUSTER_PROFILE", "test")
  cluster_profile      = lookup(local.profiles_conf.locals.profiles, local.cluster_profile_name, local.profiles_conf.locals.profiles["test"])

  deployment_env       = get_env("K8S_BOX_DEPLOYMENT_ENV", local.cluster_profile.environment)
  cluster_name         = get_env("K8S_BOX_CLUSTER_NAME", "test-cluster")
  cluster_version      = get_env("K8S_BOX_CLUSTER_VERSION", local.cluster_profile.cluster_version)
  release_channel      = get_env("K8S_BOX_RELEASE_CHANNEL", local.cluster_profile.release_channel)
  cni_type             = get_env("K8S_BOX_CNI_TYPE", local.cluster_profile.cni_type)
  enable_cilium_policy = lower(get_env("K8S_BOX_ENABLE_CILIUM_POLICY", tostring(local.cluster_profile.enable_cilium_policy))) == "true"

  subnet_cidr = get_env("K8S_BOX_SUBNET_CIDR", "10.0.1.0/24")
  master_zone = get_env("K8S_BOX_MASTER_ZONE", local.env_vars.locals.yc_zone)

  public_access               = lower(get_env("K8S_BOX_MASTER_PUBLIC_ACCESS", tostring(local.cluster_profile.public_access))) == "true"
  allow_public_load_balancers = lower(get_env("K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS", tostring(local.cluster_profile.allow_public_load_balancers))) == "true"
  master_auto_upgrade         = lower(get_env("K8S_BOX_MASTER_AUTO_UPGRADE", tostring(local.cluster_profile.master_auto_upgrade))) == "true"

  master_maintenance_day        = get_env("K8S_BOX_MASTER_MAINTENANCE_DAY", local.cluster_profile.master_maintenance.day)
  master_maintenance_start_time = get_env("K8S_BOX_MASTER_MAINTENANCE_START_TIME", local.cluster_profile.master_maintenance.start_time)
  master_maintenance_duration   = get_env("K8S_BOX_MASTER_MAINTENANCE_DURATION", local.cluster_profile.master_maintenance.duration)

  cluster_ipv4_range = get_env("K8S_BOX_CLUSTER_IPV4_RANGE", local.cluster_profile.cluster_ipv4_range)
  service_ipv4_range = get_env("K8S_BOX_SERVICE_IPV4_RANGE", local.cluster_profile.service_ipv4_range)

  node_platform_id   = get_env("K8S_BOX_NODE_PLATFORM_ID", local.cluster_profile.node.platform_id)
  node_cores         = tonumber(get_env("K8S_BOX_NODE_CORES", tostring(local.cluster_profile.node.cores)))
  node_memory_gb     = tonumber(get_env("K8S_BOX_NODE_MEMORY_GB", tostring(local.cluster_profile.node.memory_gb)))
  node_core_fraction = tonumber(get_env("K8S_BOX_NODE_CORE_FRACTION", tostring(local.cluster_profile.node.core_fraction)))
  node_boot_disk_gb  = tonumber(get_env("K8S_BOX_NODE_BOOT_DISK_GB", tostring(local.cluster_profile.node.boot_disk_gb)))
  node_preemptible   = lower(get_env("K8S_BOX_NODE_PREEMPTIBLE", tostring(local.cluster_profile.node.preemptible))) == "true"

  worker_min             = tonumber(get_env("K8S_BOX_WORKER_MIN", tostring(local.cluster_profile.worker.min)))
  worker_max             = tonumber(get_env("K8S_BOX_WORKER_MAX", tostring(local.cluster_profile.worker.max)))
  worker_initial         = tonumber(get_env("K8S_BOX_WORKER_INITIAL", tostring(local.cluster_profile.worker.initial)))
  worker_max_expansion   = tonumber(get_env("K8S_BOX_WORKER_MAX_EXPANSION", tostring(local.cluster_profile.worker.max_expansion)))
  worker_max_unavailable = tonumber(get_env("K8S_BOX_WORKER_MAX_UNAVAILABLE", tostring(local.cluster_profile.worker.max_unavailable)))

  monitoring_enabled         = lower(get_env("K8S_BOX_MONITORING_ENABLED", tostring(local.cluster_profile.monitoring.enabled))) == "true"
  monitoring_min             = tonumber(get_env("K8S_BOX_MONITORING_MIN", tostring(local.cluster_profile.monitoring.min)))
  monitoring_max             = tonumber(get_env("K8S_BOX_MONITORING_MAX", tostring(local.cluster_profile.monitoring.max)))
  monitoring_initial         = tonumber(get_env("K8S_BOX_MONITORING_INITIAL", tostring(local.cluster_profile.monitoring.initial)))
  monitoring_max_expansion   = tonumber(get_env("K8S_BOX_MONITORING_MAX_EXPANSION", tostring(local.cluster_profile.monitoring.max_expansion)))
  monitoring_max_unavailable = tonumber(get_env("K8S_BOX_MONITORING_MAX_UNAVAILABLE", tostring(local.cluster_profile.monitoring.max_unavailable)))

  # Опциональный полный override node_groups через JSON в env.
  custom_node_groups_json = trimspace(get_env("K8S_BOX_NODE_GROUPS_JSON", ""))
  use_custom_node_groups  = local.custom_node_groups_json != ""
  custom_node_groups      = local.use_custom_node_groups ? jsondecode(local.custom_node_groups_json) : {}

  use_existing_sa           = lower(get_env("K8S_BOX_USE_EXISTING_SA", "false")) == "true"
  master_service_account_id = trimspace(get_env("K8S_BOX_MASTER_SERVICE_ACCOUNT_ID", ""))
  node_service_account_id   = trimspace(get_env("K8S_BOX_NODE_SERVICE_ACCOUNT_ID", local.master_service_account_id))
  cluster_sa_name_prefix    = "k8s-service-account-${local.env_vars.locals.folder_name}"
  node_sa_name_prefix       = "k8s-node-account-${local.env_vars.locals.folder_name}"
}

inputs = {
  cloud_id                                = local.env_vars.locals.cloud_id
  folder_id                               = dependency.folder.outputs.folder_id
  main_folder_id                          = dependency.folder.outputs.folder_id
  yc_zone                                 = local.env_vars.locals.yc_zone
  master_security_group_ids               = [dependency.security-group.outputs.id]
  node_groups_default_security_groups_ids = [dependency.security-group.outputs.id]

  name                        = local.cluster_name
  cluster_name                = local.cluster_name
  master_version              = local.cluster_version
  cluster_version             = local.cluster_version # compatibility helper for old scripts/context output
  release_channel             = local.release_channel
  public_access               = local.public_access
  master_public_ip            = local.public_access
  allow_public_load_balancers = local.allow_public_load_balancers
  master_auto_upgrade         = local.master_auto_upgrade
  cni_type                    = local.cni_type
  enable_cilium_policy        = local.enable_cilium_policy
  service_account_name        = local.cluster_sa_name_prefix
  node_account_name           = local.node_sa_name_prefix
  use_existing_sa             = local.use_existing_sa
  master_service_account_id   = local.master_service_account_id != "" ? local.master_service_account_id : null
  node_service_account_id     = local.node_service_account_id != "" ? local.node_service_account_id : null

  network_id = dependency.vpc.outputs.vpc_id

  master_locations = [
    {
      zone      = local.master_zone
      subnet_id = try(dependency.vpc.outputs.private_subnets[local.subnet_cidr].subnet_id, values(dependency.vpc.outputs.private_subnets)[0].subnet_id)
    }
  ]

  master_maintenance_windows = [
    {
      day        = local.master_maintenance_day
      start_time = local.master_maintenance_start_time
      duration   = local.master_maintenance_duration
    }
  ]

  cluster_ipv4_range = local.cluster_ipv4_range
  service_ipv4_range = local.service_ipv4_range

  # По умолчанию генерируем 1-2 группы (worker/monitoring), но разрешаем полный override.
  node_groups = local.use_custom_node_groups ? local.custom_node_groups : merge(
    {
      "app-k8s-ng-01" = {
        description    = "Main application worker nodes"
        platform_id    = local.node_platform_id
        cores          = local.node_cores
        memory         = local.node_memory_gb
        core_fraction  = local.node_core_fraction
        boot_disk_size = local.node_boot_disk_gb
        preemptible    = local.node_preemptible

        auto_scale = {
          min     = local.worker_min
          max     = local.worker_max
          initial = local.worker_initial
        }

        node_locations = [
          {
            zone      = local.master_zone
            subnet_id = try(dependency.vpc.outputs.private_subnets[local.subnet_cidr].subnet_id, values(dependency.vpc.outputs.private_subnets)[0].subnet_id)
          }
        ]
        node_labels = {
          role        = "worker"
          environment = local.deployment_env
        }

        max_expansion   = local.worker_max_expansion
        max_unavailable = local.worker_max_unavailable
      }
    },
    local.monitoring_enabled ? {
      "monitoring-k8s-ng-01" = {
        description    = "Monitoring worker nodes"
        platform_id    = local.node_platform_id
        cores          = local.node_cores
        memory         = local.node_memory_gb
        core_fraction  = local.node_core_fraction
        boot_disk_size = local.node_boot_disk_gb
        preemptible    = local.node_preemptible

        auto_scale = {
          min     = local.monitoring_min
          max     = local.monitoring_max
          initial = local.monitoring_initial
        }

        node_locations = [
          {
            zone      = local.master_zone
            subnet_id = try(dependency.vpc.outputs.private_subnets[local.subnet_cidr].subnet_id, values(dependency.vpc.outputs.private_subnets)[0].subnet_id)
          }
        ]
        node_labels = {
          role            = "monitoring"
          environment     = local.deployment_env
          monitoring-node = "true"
        }

        max_expansion   = local.monitoring_max_expansion
        max_unavailable = local.monitoring_max_unavailable
      }
    } : {}
  )
}
