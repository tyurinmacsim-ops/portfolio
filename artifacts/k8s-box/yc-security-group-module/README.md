# Terraform-модуль `yc-security-group-module`

## Назначение
Создание security group и правил ingress/egress для ресурсов в VPC.

## Основные ресурсы
- `yandex_vpc_security_group`
- `yandex_vpc_security_group_rule`

## Ключевые переменные
- `network_id`, `folder_id`, `cloud_id`, `yc_token`
- `name`, `description`
- `ingress_rules_with_cidrs`, `ingress_rules_with_sg_ids`
- `egress_rules`
- `self`, `nlb_hc`

## Где используется
- Terragrunt-слой: `k8s-box/security-group/terragrunt.hcl`.
