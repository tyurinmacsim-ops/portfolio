# Terraform-модуль `yc-vpc-module`

## Назначение
Создание сетевой инфраструктуры: VPC, подсети, NAT gateway и служебные route table.

## Основные ресурсы
- `yandex_vpc_network`
- `yandex_vpc_subnet` (public/private)
- `yandex_vpc_gateway` и route table (если включен NAT)

## Ключевые переменные
- `network_name`
- `folder_id`, `cloud_id`, `yc_token`
- `private_subnets`, `public_subnets`
- `create_nat_gw`

## Outputs (основные)
- `vpc_id`
- `private_subnets`
- `public_subnets`

## Где используется
- Terragrunt-слой: `k8s-box/vpc/terragrunt.hcl`.
