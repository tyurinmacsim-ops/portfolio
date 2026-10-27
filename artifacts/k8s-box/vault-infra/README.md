# Модуль `vault-infra`

## Назначение
Terragrunt-слой для облачной инфраструктуры Vault (KMS + service accounts + optional bucket).

## Зависимости
- `../folder`

## Что делает
- Вызывает Terraform-модуль `../yc-vault-infra-module`.
- Создает KMS-ключ для auto-unseal Vault.
- Создает service account для доступа к KMS.
- Опционально создает bucket и SA для snapshot backup.

## Основные команды
```bash
cd vault-infra
terragrunt plan
terragrunt apply
terragrunt destroy
```

## Важно
- По умолчанию KMS-ключ защищен от удаления (`kms_key_deletion_protection=true`).
- Для ручного удаления можно использовать:
```bash
terragrunt destroy -var='kms_key_deletion_protection=false'
```
