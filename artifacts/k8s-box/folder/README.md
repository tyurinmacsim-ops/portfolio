# Модуль `folder`

## Назначение
Terragrunt-обертка для создания (или управления) облачным каталогом в Yandex Cloud.

## Что делает
- Вызывает Terraform-модуль `../yc-folder-module`.
- Создает folder с именем из `env.hcl` (`locals.folder_name`).
- Отдает `folder_id` в зависимости для остальных модулей.

## Откуда берутся параметры
- `cloud_id` и `folder_name` — из корневого `env.hcl`.
- Токен — из `TF_VAR_yc_token` (или авто-обновление в bootstrap/maintenance скриптах).

## Основные команды
```bash
cd folder
terragrunt plan
terragrunt apply
terragrunt destroy
```

## Важно
- Если folder с таким именем уже существует, `bootstrap-k8s-box.sh apply*` может импортировать его в state автоматически.
- Изменение `folder_name` в том же state приведет к переименованию управляемого folder, а не к созданию второго.
