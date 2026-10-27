locals {
  iam_defaults = {
    service_account_name = "k8s-service-account-${var.cluster_name}"
    node_account_name    = "k8s-node-account-${var.cluster_name}"
  }
  use_existing_sa = var.use_existing_sa && var.master_service_account_id != null && var.node_service_account_id != null

  node_groups_need_public_admin = anytrue([for i, v in var.node_groups : lookup(v, "nat", var.node_groups_defaults.nat)])
  master_needs_public_admin     = var.public_access || var.master_public_ip
  cross_folder_vpc              = var.main_folder_id != "" && var.main_folder_id != var.folder_id
  effective_master_sa_id        = local.use_existing_sa ? var.master_service_account_id : yandex_iam_service_account.master[0].id
  effective_node_sa_id          = local.use_existing_sa ? var.node_service_account_id : yandex_iam_service_account.node_account[0].id
}

resource "yandex_iam_service_account" "master" {
  count     = local.use_existing_sa ? 0 : 1
  folder_id = var.folder_id
  name      = try("${var.service_account_name}-${var.cluster_name}", local.iam_defaults.service_account_name)
}

resource "yandex_iam_service_account" "node_account" {
  count     = local.use_existing_sa ? 0 : 1
  folder_id = var.folder_id
  name      = try("${var.node_account_name}-${var.cluster_name}", local.iam_defaults.node_account_name)
}

resource "yandex_resourcemanager_folder_iam_member" "sa_calico_network_policy_role" {
  count     = var.enable_cilium_policy ? 0 : 1
  folder_id = var.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_cilium_network_policy_role" {
  count     = var.enable_cilium_policy ? 1 : 0
  folder_id = var.folder_id
  role      = "k8s.tunnelClusters.agent"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_node_group_public_role_admin" {
  count     = (local.node_groups_need_public_admin || local.master_needs_public_admin) ? 1 : 0
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_node_group_loadbalancer_role_admin" {
  count     = local.node_groups_need_public_admin ? 1 : 0
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_public_loadbalancers_role" {
  count     = var.allow_public_load_balancers ? 1 : 0
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_vpc_private_admin_role" {
  count     = local.cross_folder_vpc ? 1 : 0
  folder_id = var.main_folder_id
  role      = "vpc.privateAdmin"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_vpc_user_role" {
  count     = local.cross_folder_vpc ? 1 : 0
  folder_id = var.main_folder_id
  role      = "vpc.user"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_vpc_bridge_admin_role" {
  count     = local.cross_folder_vpc ? 1 : 0
  folder_id = var.main_folder_id
  role      = "vpc.bridgeAdmin"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_vpc_public_admin_role" {
  count     = local.cross_folder_vpc && (local.master_needs_public_admin || local.node_groups_need_public_admin || var.allow_public_load_balancers) ? 1 : 0
  folder_id = var.main_folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_vpc_public_local_admin_role" {
  count     = local.cross_folder_vpc && (local.master_needs_public_admin || local.node_groups_need_public_admin || var.allow_public_load_balancers) ? 1 : 0
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_logging_writer_role" {
  count     = var.master_logging.enabled ? 1 : 0
  folder_id = var.folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${local.effective_master_sa_id}"
}

resource "yandex_resourcemanager_folder_iam_member" "node_account" {
  count     = 1
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${local.effective_node_sa_id}"
}
