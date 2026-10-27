data "yandex_compute_image" "boot" {
  family = var.boot_image_family
}

locals {
  use_created_sa = var.service_account_id == "" && var.create_service_account
  effective_sa_id = var.service_account_id != "" ? var.service_account_id : (
    local.use_created_sa ? yandex_iam_service_account.vpn[0].id : null
  )

  effective_security_group_ids = concat(
    var.additional_security_group_ids,
    var.create_security_group ? [yandex_vpc_security_group.vpn[0].id] : []
  )
}

resource "yandex_iam_service_account" "vpn" {
  count     = local.use_created_sa ? 1 : 0
  folder_id = var.folder_id
  name      = var.service_account_name
}

resource "yandex_resourcemanager_folder_iam_member" "vpn_sa_roles" {
  for_each = local.use_created_sa ? toset(var.service_account_roles) : toset([])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.vpn[0].id}"
}

resource "yandex_vpc_security_group" "vpn" {
  count = var.create_security_group ? 1 : 0

  folder_id   = var.folder_id
  network_id  = var.network_id
  name        = "${var.name}-sg"
  description = "Security group for ${var.name}"

  ingress {
    description    = "SSH access"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.admin_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_openvpn ? [1] : []
    content {
      description    = "OpenVPN access"
      protocol       = "UDP"
      port           = var.openvpn_port
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_wireguard ? [1] : []
    content {
      description    = "WireGuard access"
      protocol       = "UDP"
      port           = var.wireguard_port
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description    = "Allow all outbound traffic"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "vpn" {
  name        = var.name
  folder_id   = var.folder_id
  zone        = var.yc_zone
  platform_id = var.platform_id

  resources {
    cores         = var.cores
    memory        = var.memory
    core_fraction = var.core_fraction
  }

  boot_disk {
    initialize_params {
      size     = var.boot_disk_size
      type     = var.boot_disk_type
      image_id = data.yandex_compute_image.boot.id
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = var.nat
    security_group_ids = local.effective_security_group_ids
  }

  service_account_id        = local.effective_sa_id
  allow_stopping_for_update = var.allow_stopping_for_update

  metadata = {
    user-data          = var.user_data
    enable-oslogin     = tostring(var.enable_oslogin)
    serial-port-enable = "1"
    ssh-keys           = !var.enable_oslogin && trimspace(var.ssh_public_key) != "" ? "${var.ssh_username}:${trimspace(var.ssh_public_key)}" : null
  }

  labels = var.labels
}
