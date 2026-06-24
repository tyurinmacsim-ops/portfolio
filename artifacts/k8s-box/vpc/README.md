# Модуль `vpc`

## Назначение
Terragrunt-слой для создания сети VPC, подсетей и NAT.

## Зависимости
- `../folder` (используется `dependency.folder.outputs.folder_id`).

## Что делает
- Вызывает Terraform-модуль `../yc-vpc-module`.
- Создает сеть с именем из `env.hcl` (`network_name`).
- Создает private subnet (по умолчанию `10.0.1.0/24` в `ru-central1-a`).
- Включает NAT gateway (`create_nat_gw = true`).

## Основные команды
```bash
cd vpc
terragrunt plan
terragrunt apply
terragrunt destroy
```

## Важно
- `network_name` и `cloud_id` берутся из `env.hcl`.
- Все зависимые модули используют `vpc_id` и `private_subnets` из outputs этого модуля.
