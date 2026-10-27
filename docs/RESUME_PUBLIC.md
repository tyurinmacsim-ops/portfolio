# Резюме

## Максим Тюрин

- Роль: `DevOps / Platform Engineer`
- Локация: `Пермь`
- Формат работы: `удалённо`, готов к редким командировкам
- Контакты: `tyurinmacsim@gmail.com`, `@Max_Tyrin`

## Кратко

DevOps / Platform Engineer с `4+` годами коммерческого опыта в DevOps и `9+` годами в IT.

Основной стек:

- `Linux`, `Docker`, `Kubernetes`, `Helm`
- `GitLab CI/CD`, `ArgoCD`, `FluxCD`
- `OpenTofu/Terraform`, `Terragrunt`, `Ansible`
- `AWS`, `Azure`, `Yandex Cloud`, `Selectel`
- `PostgreSQL`, `Redis`, `Kafka`, `RabbitMQ`, `MongoDB`, `ClickHouse`
- `Prometheus`, `Grafana`, `Loki`, `VictoriaMetrics`, `Vault`

## Ключевые результаты

- сократил время релиза с `1.5 часов` до `10–15 минут`;
- повысил частоту релизов с `1–2` до `5–10` в день;
- снизил `MTTR` на `45–60%` за счёт мониторинга и алертинга;
- оптимизировал cloud-расходы на `15–35%` в разных контурах;
- сопровождал production-инфраструктуру для `100+` микросервисов.

## Опыт

### PERX / MyNaghi | 2026-08 — 2026-10

Инфраструктура Perx и MyNaghi в Yandex Cloud, AWS, Selectel и bare-metal Kubernetes; production и dev/stage.

- OpenTofu/Terraform для сетей, ВМ, Kubernetes и managed PostgreSQL. В GitLab CI выстроил validate → plan → контролируемый apply, проверки drift и зависимости между стеками.
- Развивал приватный delivery-контур: GitLab Runner с доступом через NetBird и мониторингом, Ansible для хостов, Helm и Argo CD для релизов.
- Для Airflow/importer настроил ресурсы и параллелизм; автоматизировал временные worker-ноды через Crossplane в Yandex Cloud и AWS. Добавил безопасную очистку устаревших Node после проверки отсутствия ВМ и активных pod.
- В Prometheus/Grafana разобрал причины повторных алертов Kubernetes и серверов, исправил правила; устранил ложный `KubeDaemonSetRolloutStuck` от потерянных worker-нод.
- Поэтапно обновил Traefik на `22` Selectel-ВМ и проверил состояние сервисов. Участвовал в восстановлении сайтов после сбоя зон Yandex Cloud и подготовке переноса сервисов на Selectel.
- Для MyNaghi сопровождал публикацию сайта из S3 через CloudFront и управление кэшем. [Разбор решений и методика](./ACTIVITY_2026.md).

### Hilbert Team | 2025-12 — 2026-03

- `Yandex Cloud`, `Kubernetes`, `Terraform/Terragrunt`, `GitLab CI/CD`, `Helm`
- monitoring / alerting: `Prometheus`, `VictoriaMetrics`, `Grafana`, `Loki`
- сопровождение `PostgreSQL`, `MongoDB`, `ClickHouse`, `Kafka`, `RabbitMQ`

### 01.tech | 2023-09 — 2025-11

- `AWS`, `EKS`, `Kubernetes`, `Docker`, `Helm`
- `GitLab CI/CD`, `ArgoCD`, `Terraform`, `Terragrunt`
- production-контур с `100+` микросервисами
- асинхронные Telegram-контуры с массовой доставкой и большими очередями до `10 млн` сообщений
- adjacent platform/data tooling в зоне `tgbot/tgbots`: `Retool`, `Debezium`, migration jobs и migration/revert-процессы вокруг сервисных БД
- deployment-связки для Telegram bot/API-сервисов: `Helm`, `ArgoCD ApplicationSet`, values по окружениям, `Vault`, `ExternalDNS`, `Istio Gateway`
- администрирование `FortiGate/FortiClient VPN` для доступа к tgbots-контурам: сетевые объекты, маршрутизация и политики доступа
- observability: `Prometheus`, `Grafana`, `Loki`, `VictoriaMetrics`

### xero | 2022-07 — 2023-08

- `Azure`, `AKS`, `Terraform/Terragrunt`
- `FluxCD`, `GitLab CI`, private ingress, `Key Vault`
- подготовка инфраструктурного контура к `PCI DSS`

### SWAPP Protocol | 2021-11 — 2022-06

- `AWS`, `Hetzner`, `Terraform`, `Ansible`
- `Docker`, `Kubernetes`, `Proxmox`, `Cloudflare`
- `PostgreSQL`, `MySQL`, `Redis`, `ClickHouse`

## Дополнение

- Связка с доказательствами в портфолио: [Сопоставление резюме и портфолио](./RESUME_PORTFOLIO_MAP.md)
- Публичные артефакты: [Дополнительные артефакты](./ARTIFACT_EVIDENCE.md)
