resource "yandex_logging_group" "main" {
  folder_id = var.folder_id
  count     = var.master_logging["create_log_group"] ? 1 : 0

  name   = var.name
  labels = var.labels

  retention_period = var.master_logging["log_group_retention_period"]
}

resource "time_sleep" "after_cluster_iam" {
  create_duration = "${var.cluster_create_iam_delay_seconds}s"

  depends_on = [
    yandex_resourcemanager_folder_iam_member.node_account,
    yandex_resourcemanager_folder_iam_member.sa_calico_network_policy_role,
    yandex_resourcemanager_folder_iam_member.sa_cilium_network_policy_role,
    yandex_resourcemanager_folder_iam_member.sa_node_group_public_role_admin,
    yandex_resourcemanager_folder_iam_member.sa_node_group_loadbalancer_role_admin,
    yandex_resourcemanager_folder_iam_member.sa_public_loadbalancers_role,
    yandex_resourcemanager_folder_iam_member.sa_vpc_private_admin_role,
    yandex_resourcemanager_folder_iam_member.sa_vpc_user_role,
    yandex_resourcemanager_folder_iam_member.sa_vpc_bridge_admin_role,
    yandex_resourcemanager_folder_iam_member.sa_vpc_public_admin_role,
    yandex_resourcemanager_folder_iam_member.sa_vpc_public_local_admin_role,
    yandex_resourcemanager_folder_iam_member.sa_logging_writer_role
  ]
}

resource "yandex_kubernetes_cluster" "main" {
  folder_id = var.folder_id

  name        = var.name
  description = var.description
  labels      = var.labels

  network_id               = var.network_id
  cluster_ipv4_range       = var.cluster_ipv4_range
  cluster_ipv6_range       = var.cluster_ipv6_range
  node_ipv4_cidr_mask_size = var.node_ipv4_cidr_mask_size
  service_ipv4_range       = var.service_ipv4_range
  service_ipv6_range       = var.service_ipv6_range

  dynamic "network_implementation" {
    for_each = var.cni_type == "cilium" ? [1] : []
    content {
      cilium {}
    }
  }

  service_account_id      = local.effective_master_sa_id
  node_service_account_id = local.effective_node_sa_id

  release_channel         = var.release_channel
  network_policy_provider = var.cni_type == "calico" ? "CALICO" : null

  dynamic "kms_provider" {
    for_each = var.kms_provider_key_id != null ? [var.kms_provider_key_id] : []

    content {
      key_id = kms_provider.value
    }
  }

  master {
    version            = var.master_version
    public_ip          = var.master_public_ip
    security_group_ids = var.master_security_group_ids

    maintenance_policy {
      auto_upgrade = var.master_auto_upgrade

      dynamic "maintenance_window" {
        for_each = var.master_maintenance_windows

        content {
          day        = lookup(maintenance_window.value, "day", null)
          start_time = maintenance_window.value["start_time"]
          duration   = maintenance_window.value["duration"]
        }
      }
    }

    dynamic "zonal" {
      for_each = local.master_locations

      content {
        zone      = zonal.value["zone"]
        subnet_id = zonal.value["subnet_id"]
      }
    }

    dynamic "regional" {
      for_each = local.master_regions

      content {
        region = regional.value["region"]

        dynamic "location" {
          for_each = regional.value["locations"]

          content {
            zone      = location.value["zone"]
            subnet_id = location.value["subnet_id"]
          }
        }
      }
    }

    master_logging {
      enabled                    = var.master_logging["enabled"]
      log_group_id               = var.master_logging["log_group_id"] != "" ? var.master_logging["log_group_id"] : (var.master_logging["create_log_group"] ? yandex_logging_group.main[0].id : null)
      audit_enabled              = var.master_logging["enabled"] ? var.master_logging["audit_enabled"] : null
      kube_apiserver_enabled     = var.master_logging["enabled"] ? var.master_logging["kube_apiserver_enabled"] : null
      cluster_autoscaler_enabled = var.master_logging["enabled"] ? var.master_logging["cluster_autoscaler_enabled"] : null
      events_enabled             = var.master_logging["enabled"] ? var.master_logging["events_enabled"] : null
    }
  }

  depends_on = [
    time_sleep.after_cluster_iam
  ]
}
