data "yandex_compute_image" "boot" {
  family = var.boot_image_family
}

locals {
  use_created_sa = var.service_account_id == "" && var.create_service_account
  effective_sa_id = var.service_account_id != "" ? var.service_account_id : (
    local.use_created_sa ? yandex_iam_service_account.runner[0].id : null
  )
}

resource "yandex_iam_service_account" "runner" {
  count     = local.use_created_sa ? 1 : 0
  folder_id = var.folder_id
  name      = var.service_account_name
}

resource "yandex_resourcemanager_folder_iam_member" "runner_sa_roles" {
  for_each = local.use_created_sa ? toset(var.service_account_roles) : toset([])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.runner[0].id}"
}

resource "yandex_compute_instance" "runner" {
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
    security_group_ids = var.security_group_ids
  }

  service_account_id        = local.effective_sa_id
  allow_stopping_for_update = var.allow_stopping_for_update

  metadata = {
    user-data          = var.user_data
    enable-oslogin     = tostring(var.enable_oslogin)
    serial-port-enable = "1"
  }

  lifecycle {
    # cloud-init user-data is bootstrap-only; keep plans stable after first creation
    ignore_changes = [metadata["user-data"]]
  }

  labels = var.labels
}
