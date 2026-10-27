# Terraform-модуль `yc-vault-infra-module`

## Назначение
Подготовка облачной инфраструктуры для Vault:
- KMS-ключ для auto-unseal,
- service account для доступа к KMS,
- опционально bucket/ключи для snapshot backup.

## Основные ресурсы
- `yandex_kms_symmetric_key`
- `yandex_iam_service_account`
- `yandex_iam_service_account_key`
- `yandex_storage_bucket` (опционально)

## Ключевые переменные
- `cloud_id`, `folder_id`, `yc_token`
- `kms_key_name`, `kms_key_rotation_period`
- `kms_key_deletion_protection`
- `vault_kms_sa_name`, `create_kms_sa_key`
- `create_backup_bucket`, `backup_bucket_name`, `backup_bucket_force_destroy`

## Где используется
- Terragrunt-слой: `k8s-box/vault-infra/terragrunt.hcl`.

## Важно
- По умолчанию `kms_key_deletion_protection=true`, что защищает ключ от случайного удаления.
