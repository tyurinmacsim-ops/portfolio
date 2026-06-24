output "folder_id" {
  value = values(yandex_resourcemanager_folder.folders)[0].id
}