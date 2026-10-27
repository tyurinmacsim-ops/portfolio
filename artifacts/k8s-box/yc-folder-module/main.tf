resource "yandex_resourcemanager_folder" "folders" {
  for_each = var.folders

  cloud_id    = each.value.cloud_id
  name        = each.value.folder_name
  description = each.value.folder_description
}

