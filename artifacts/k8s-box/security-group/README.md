# Модуль `security-group`

## Назначение
Terragrunt-слой для сетевых правил доступа Kubernetes-кластера.

## Зависимости
- `../folder`
- `../vpc`

## Что делает
- Вызывает Terraform-модуль `../yc-security-group-module`.
- Создает security group `k8s-cluster-sg`.
- Настраивает ingress/egress правила для API, SSH, ICMP и внутреннего трафика кластера.

## Основные команды
```bash
cd security-group
terragrunt plan
terragrunt apply
terragrunt destroy
```

## Важно
- Правило для Kubernetes API (TCP 443) по умолчанию открыто на `0.0.0.0/0`.
- Для прод-сценария рекомендуется ограничить CIDR до административных IP.
- Правило `nlb_hc` теперь профильно переключается:
  - `test` -> выключено по умолчанию;
  - `dev/prod` -> включено по умолчанию.
