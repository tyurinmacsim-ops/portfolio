# Terraform-модуль `yc-folder-module`

## Назначение
Создание папки (folder) в Yandex Cloud.

## Основные ресурсы
- `yandex_resourcemanager_folder`

## Ключевые переменные
- `folders` — map с описанием folder (cloud_id, folder_name, description).
- `cloud_id` — cloud, в котором создается folder.
- `yc_token` — токен провайдера Yandex.

## Outputs
- `folder_id`

## Где используется
- Terragrunt-слой: `k8s-box/folder/terragrunt.hcl`.
